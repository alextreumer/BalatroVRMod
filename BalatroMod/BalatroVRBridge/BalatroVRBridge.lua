--- STEAMODDED HEADER
--- MOD_NAME: Balatro in VR
--- MOD_ID: BalatroVRBridge
--- MOD_AUTHOR: [UnderTheVRadar]
--- VERSION: 1.0
--- MOD_DESCRIPTION: Play Balatro in VR: the whole game around you in a virtual casino, with your cards in your hand and 3D jokers on the table. Needs the "Balatro in VR" client - youtube.com/@UnderTheVRadar

----------------------------------------------
------------MOD CODE -------------------------

-- Protocol v2 (see Docs/PROTOCOL.md)
--   The VR client is the TCP server on 127.0.0.1:27801; this mod connects as client and reconnects
--   automatically. Every message is one JSON object per line ("\n"-terminated), both directions.
--   Game -> VR : {"type":"scene"|"state"|"event"|"ack","seq":n,"v":2,"data":{...}}
--   VR -> Game : {"cmd":"click"|"hover"|"unhover"|"play"|"discard"|"highlight"|"button"|"ping","id":n,...}

local socket = require("socket")

local CFG = {
    host = "127.0.0.1",
    port = 27801,
    scene_interval = 1 / 15,   -- max. scene snapshots per second (only sent when something changed)
    state_interval = 1 / 10,   -- max. semantic state messages per second
    heartbeat_interval = 1.0,  -- resend unchanged snapshots so the client can detect a dead link
    connect_retry = 1.0,       -- seconds between connection attempts
    connect_timeout = 3.0,
    max_queue_bytes = 32 * 1024 * 1024, -- texture atlases can be a few MB each
    command_timeout = 3.0,     -- drop gated commands that could not run for this long
    protocol_version = 2,
}

local VR = {
    seq = 0,
    last_scene = nil, last_scene_time = 0, last_scene_send = 0,
    last_state = nil, last_state_time = 0, last_state_send = 0,
    pending_releases = {},     -- gamepad buttons to release on the next frame ("tap")
    queue = {},                -- gated commands waiting for the game to accept input
    sent_atlas = {},           -- texture atlases already sent over the current connection
    last_error = nil,
    floor = { cm = 0 },        -- the casino floor height the VR client uses (slider in VR Settings)
}
BalatroVR = VR -- global for debugging from the Lovely console

local function log(msg) print("[BalatroVR] " .. msg) end

-- Test helper for trying out jokers: F8 (keyboard) or "Test: +$10000" in the Options menu gives
-- money during a run; F9 or "Test: Extreme" gives more hand size and joker / consumable slots.
-- Set to false before sharing the mod.
local TEST_MONEY = false
local TEST_MONEY_AMOUNT = 10000

----------------------------------------------------------------------------
-- Minimal JSON encoder (arrays are marked explicitly so empty lists stay [])
----------------------------------------------------------------------------
local ARRAY_MT = { __jsontype = "array" }
local function arr(t) return setmetatable(t or {}, ARRAY_MT) end

local ESCAPES = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
local function escape_str(s)
    return (s:gsub('[%c"\\]', function(c) return ESCAPES[c] or string.format("\\u%04x", c:byte()) end))
end

local function encode(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        if math.floor(v) == v then return string.format("%.0f", v) end
        local s = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
        return s
    elseif t == "string" then return '"' .. escape_str(v) .. '"'
    elseif t == "table" then
        local out = {}
        if getmetatable(v) == ARRAY_MT or #v > 0 then
            for i = 1, #v do out[i] = encode(v[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        -- sorted keys => identical content produces identical strings (cheap change detection)
        local keys = {}
        for k, val in pairs(v) do
            if type(val) ~= "function" then keys[#keys + 1] = tostring(k) end
        end
        table.sort(keys)
        for i, k in ipairs(keys) do out[i] = encode(k) .. ":" .. encode(v[k]) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

-- Commands from the client are flat objects, e.g. {"cmd":"click","target":42,"id":7}
local function decode_flat(s)
    local msg = {}
    for k, raw in s:gmatch('"([%w_]+)"%s*:%s*("?[^,}"]*"?)') do
        if raw:sub(1, 1) == '"' then msg[k] = raw:sub(2, -2)
        elseif raw == "true" then msg[k] = true
        elseif raw == "false" then msg[k] = false
        else msg[k] = tonumber(raw) end
    end
    return msg
end

----------------------------------------------------------------------------
-- TCP transport (non-blocking, newline framed, auto-reconnect)
----------------------------------------------------------------------------
local NET = { tcp = nil, state = "idle", next_try = 0, started = 0, out = {}, out_bytes = 0, send_pos = 1, rx = "" }

local function net_close(reason)
    if NET.tcp then pcall(function() NET.tcp:close() end) end
    if NET.state == "connected" then log("disconnected (" .. tostring(reason) .. ")") end
    NET.tcp, NET.state = nil, "idle"
    NET.out, NET.out_bytes, NET.send_pos, NET.rx = {}, 0, 1, ""
end

local function net_on_connected()
    NET.state = "connected"
    log("connected to VR client on port " .. CFG.port)
    -- force full snapshots, textures and the font for the new client
    VR.last_scene, VR.last_state = nil, nil
    VR.sent_atlas = {}
    VR.sent_font = false
    VR.sent_intro = false
    VR.sent_sounds = {}
end

local function net_update_connection(now)
    if NET.state == "connected" then return true end

    if NET.state == "idle" then
        if now < NET.next_try then return false end
        NET.next_try = now + CFG.connect_retry
        local tcp = socket.tcp()
        tcp:settimeout(0)
        pcall(function() tcp:setoption("tcp-nodelay", true) end)
        local ok, err = tcp:connect(CFG.host, CFG.port)
        NET.tcp, NET.started = tcp, now
        if ok then net_on_connected(); return true end
        if err == "timeout" or err == "Operation already in progress" then
            NET.state = "connecting"
        else
            net_close(err)
        end
        return false
    end

    -- connecting: writable socket + peer name => connected
    local _, writable = socket.select(nil, { NET.tcp }, 0)
    if writable and (writable[1] or writable[NET.tcp]) and NET.tcp:getpeername() then
        net_on_connected()
        return true
    end
    if now - NET.started > CFG.connect_timeout then net_close("connect timeout") end
    return false
end

local function net_queue(line)
    if NET.state ~= "connected" then return end
    if NET.out_bytes > CFG.max_queue_bytes then
        -- client is not reading; keep only a partially sent message to preserve framing
        local keep = (NET.send_pos > 1) and NET.out[1] or nil
        NET.out, NET.out_bytes = { keep }, keep and #keep or 0
        VR.last_scene, VR.last_state = nil, nil
        VR.sent_atlas = {}
        VR.sent_font = false
        VR.sent_intro = false
        VR.sent_sounds = {}
    end
    NET.out[#NET.out + 1] = line
    NET.out_bytes = NET.out_bytes + #line
end

local function net_flush()
    while NET.state == "connected" and NET.out[1] do
        local msg = NET.out[1]
        local last, err, partial = NET.tcp:send(msg, NET.send_pos)
        if last then
            table.remove(NET.out, 1)
            NET.out_bytes = NET.out_bytes - #msg
            NET.send_pos = 1
        elseif err == "timeout" then
            NET.send_pos = (partial or (NET.send_pos - 1)) + 1
            return
        else
            net_close(err)
            return
        end
    end
end

local function net_receive(handle_line)
    for _ = 1, 64 do -- bounded so a flood can't stall a frame
        if NET.state ~= "connected" then return end
        local line, err, partial = NET.tcp:receive("*l", NET.rx)
        if line then
            NET.rx = ""
            handle_line(line)
        elseif err == "timeout" then
            NET.rx = partial or ""
            return
        else
            net_close(err)
            return
        end
    end
end

local function send(msg_type, data_json)
    VR.seq = VR.seq + 1
    net_queue('{"type":"' .. msg_type .. '","seq":' .. VR.seq .. ',"v":' .. CFG.protocol_version .. ',"data":' .. data_json .. '}\n')
end

function VR.send_event(name, fields)
    fields = fields or {}
    fields.event = name
    send("event", encode(fields))
end

----------------------------------------------------------------------------
-- Object ids: stable numbers for every UI element / card / area we mirror
----------------------------------------------------------------------------
local ids = setmetatable({}, { __mode = "k" })
local objs = setmetatable({}, { __mode = "v" })
local next_id = 0

local function oid(o)
    local id = ids[o]
    if not id then
        next_id = next_id + 1
        id = next_id
        ids[o] = id
        objs[id] = o
    end
    return id
end

local function is_a(x, cls)
    return type(x) == "table" and cls ~= nil and type(x.is) == "function" and x:is(cls)
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function num(x)
    if type(x) == "table" and x.to_number then return x:to_number() end -- Talisman big numbers
    return tonumber(x) or 0
end

local function r2(x) x = num(x); return math.floor(x * 100 + 0.5) / 100 end
local function r3(x) x = num(x); return math.floor(x * 1000 + 0.5) / 1000 end

local function col(c)
    if type(c) ~= "table" then return nil end
    return arr({ r3(c[1] or 1), r3(c[2] or 1), r3(c[3] or 1), r3(c[4] or 1) })
end

-- position/size of anything drawable; VT is what the game actually draws (absolute room units)
local function put_rect(item, o)
    local t = o.VT or o.T
    if not t then return false end
    item.x, item.y, item.w, item.h = r2(t.x), r2(t.y), r2(t.w), r2(t.h)
    return true
end

local STATE_NAMES = nil
local function state_name(s)
    if not STATE_NAMES then
        STATE_NAMES = {}
        for k, v in pairs(G.STATES) do STATE_NAMES[v] = k end
    end
    return STATE_NAMES[s] or tostring(s)
end

----------------------------------------------------------------------------
-- Scene mirror: every visible UI node, card and card area in draw order
----------------------------------------------------------------------------
local AREA_NAMES = { "hand", "jokers", "consumeables", "deck", "discard", "play",
                     "shop_jokers", "shop_vouchers", "shop_booster", "pack_cards", "title_top" }
local BOX_ROLES = { "HUD", "HUD_blind", "buttons", "shop", "blind_select", "round_eval", "booster_pack",
                    "OVERLAY_MENU", "MAIN_MENU_UI", "SHOP_SIGN", "PROFILE_BUTTON", "blind_prompt_box" }

local SCN -- per-snapshot context

local emit_box, emit_area, emit_card

local function add(item)
    item.g = SCN.group
    -- run panel: the ids of all enclosing UI nodes ("/row_round/hud_hands/"), so the client can
    -- show a compact panel outside of rounds
    if SCN.track_ids and #SCN.idpath > 0 then
        item.ids = "/" .. table.concat(SCN.idpath, "/") .. "/"
    end
    SCN.items[#SCN.items + 1] = item
end

local function use_atlas(name)
    if type(name) == "string" and name ~= "" then SCN.atlases[name] = true end
end

-- tooltips are drawn last; remember the card they belong to so VR can place them next to it
local function queue_popup(box, owner)
    SCN.late[#SCN.late + 1] = { box = box, owner = owner }
end

local function clickable(e)
    local cfg = e.config
    if e.under_overlay or e.disable_button then return false end
    if cfg.button then return true end
    return cfg.button_UIE ~= nil and cfg.button_UIE.config ~= nil and cfg.button_UIE.config.button ~= nil
end

-- The score flames behind chips/mult are a sprite the game draws through its 'flame' shader;
-- without that shader it is just a raw icon. Send the flame strength instead (only while burning).
-- The score flames' state in G.ARGS: Steamodded's scoring parameters call the chips flame
-- "chips_flames" (vanilla: "chip_flames"), so the first name that exists wins.
local FLAMES = { flame_chips = { "chips_flames", "chip_flames" }, flame_mult = { "mult_flames" } }

local function flame_args(names)
    for _, name in ipairs(names) do
        local args = G.ARGS and G.ARGS[name]
        if args then return args end
    end
    return nil
end

-- Where a sprite sits in its atlas: Sprite keeps it in sprite_pos, AnimatedSprite (blind chips,
-- also as card faces in the Blinds collection) in animation.x / .y
local function sprite_xy(s)
    if type(s) ~= "table" then return nil end
    local p = s.sprite_pos
    if not (type(p) == "table" and p.x and p.y) then p = s.animation end
    if type(p) == "table" and p.x and p.y then return p end
    return nil
end

local function emit_object(obj, holder)
    -- hidden objects stay hidden: e.g. the tick of an unchecked toggle is a sprite with visible = false
    if type(obj) == "table" and obj.states and obj.states.visible == false then return end
    local flame = holder and holder.config and FLAMES[holder.config.id]
    if flame then
        local args = flame_args(flame)
        local intensity = args and num(args.real_intensity or args.intensity) or 0
        if intensity > 0.01 then
            local item = { k = "fl", id = oid(obj), i = r3(intensity), c = col(args.colour_1), c2 = col(args.colour_2) }
            if put_rect(item, holder.parent or holder) then add(item) end -- the chips/mult box it burns on
        end
        return
    end
    if is_a(obj, UIBox) then
        emit_box(obj)
    elseif is_a(obj, CardArea) then
        emit_area(obj)
    elseif is_a(obj, Card) then
        emit_card(obj, nil)
    elseif Card_Character and is_a(obj, Card_Character) then
        -- Jimbo on the Game Over / win screen: the joker card, his speech bubble, his button
        local ch = obj.children or {}
        if ch.card then emit_card(ch.card, nil) end
        if ch.speech_bubble then emit_box(ch.speech_bubble) end
        if ch.button and not obj.talking then emit_box(ch.button) end
    elseif type(obj) == "table" and obj.strings and obj.focused_string then -- DynaText
        local s = obj.strings[obj.focused_string]
        local text = s and s.string
        if type(text) == "string" and text ~= "" then
            local item = { k = "t", id = oid(obj), s = text, c = col(obj.colours and obj.colours[1]), dyn = true }
            -- the letter animations of this text; the VR client replays them with its own clock
            local cfg = obj.config or {}
            local fx = {}
            if cfg.bump then fx.bump = r3(obj.bump_amount or 1); fx.br = r3(obj.bump_rate or 2.666) end
            if cfg.float then fx.float = true end
            if cfg.rotate then fx.rot = (cfg.rotate == 2) and -1 or 1 end
            if cfg.quiver then fx.q = r3(cfg.quiver.amount or 0.7); fx.qs = r3(cfg.quiver.speed or 0.5) end
            if next(fx) then item.fx = fx end
            if put_rect(item, obj.VT and obj or holder) then add(item) end
        end
    elseif type(obj) == "table" and obj.atlas and sprite_xy(obj) then -- Sprite / AnimatedSprite
        local xy = sprite_xy(obj)
        local item = { k = "s", id = oid(obj), a = obj.atlas.name or "", p = arr({ num(xy.x), num(xy.y) }) }
        -- a sprite with its own tooltip (tags: the skip reward on the blind select, the run panel's
        -- tags): VR may point at it and "hover" it like a card
        if rawget(obj, "hover") and obj.states and obj.states.hover and obj.states.hover.can then item.hv = true end
        if put_rect(item, obj) then add(item); use_atlas(item.a) end
    end
end

local function emit_node(e)
    local cfg = e.config or {}
    -- like UIElement:draw_children: an invisible element hides its whole subtree
    -- (e.g. "DEFEAT BOSS BLIND TO RESTOCK" in the voucher slot while a voucher is for sale)
    if e.states and e.states.visible == false then return end
    local tracked = SCN.track_ids and type(cfg.id) == "string"
    if tracked then SCN.idpath[#SCN.idpath + 1] = cfg.id end
    do
        local click = clickable(e)
        if e.UIT == G.UIT.T then
            local text = cfg.text
            if text ~= nil and text ~= "" then
                local item = { k = "t", id = oid(e), s = tostring(text), c = col(cfg.colour) }
                if cfg.vert then item.vert = true end
                if click then item.b = true end
                if cfg.button_UIE and not cfg.button_UIE.config.button then item.off = true end
                if put_rect(item, e) then add(item) end
            end
        elseif e.UIT == G.UIT.O then
            if cfg.object then emit_object(cfg.object, e) end
            if click then -- objects can be buttons too (e.g. deck/stake selectors)
                local item = { k = "r", id = oid(e), b = true }
                if put_rect(item, e) then add(item) end
            end
        else
            local c = cfg.colour
            local visible = type(c) == "table" and (c[4] or 1) > 0.01
            local slider = cfg.func == "slider" -- the track of a slider (volume ...): VR drags it with the beam
            if visible or click or slider then
                local item = { k = "r", id = oid(e) }
                if visible then item.c = col(c) end
                if click or slider then item.b = true end
                if slider then item.sl = true end
                if cfg.r then item.rr = true end
                if cfg.outline and cfg.outline_colour and (cfg.outline_colour[4] or 1) > 0.01 then item.oc = col(cfg.outline_colour) end
                if cfg.progress_bar and cfg.progress_bar.ref_table then
                    item.pb = r3(num(cfg.progress_bar.ref_table[cfg.progress_bar.ref_value]) / math.max(num(cfg.progress_bar.max), 1e-6))
                end
                if put_rect(item, e) then add(item) end
            end
        end
    end
    for k, child in pairs(e.children or {}) do
        if is_a(child, UIBox) then
            if k == "h_popup" then queue_popup(child) else emit_box(child) end
        elseif type(child) == "table" and child.UIT then
            emit_node(child)
        end
    end
    if tracked then SCN.idpath[#SCN.idpath] = nil end
end

emit_box = function(box)
    if SCN.emitted[box] then return end
    SCN.emitted[box] = true
    if box.states and box.states.visible == false then return end

    for k, child in pairs(box.children or {}) do
        if is_a(child, UIBox) and k ~= "alert" then
            if k == "h_popup" then queue_popup(child) else emit_box(child) end
        end
    end
    if box.UIRoot then emit_node(box.UIRoot) end
    if box.children and is_a(box.children.alert, UIBox) then emit_box(box.children.alert) end
end

-- The stickers a card wears (Eternal, Perishable, Rental, stake stickers, mod stickers, the seal),
-- each a sprite {a = atlas, p = {x, y}}. Used for the cards in the scene and for the 3D jokers.
local function card_stickers(card)
    local a = card.ability or {}
    local ov = arr()
    local function overlay(sprite)
        local xy = sprite_xy(sprite)
        if sprite and sprite.atlas and sprite.atlas.name and xy then
            ov[#ov + 1] = { a = sprite.atlas.name, p = arr({ num(xy.x), num(xy.y) }) }
        end
    end
    if card.seal and G.shared_seals then overlay(G.shared_seals[card.seal]) end
    if a.eternal then overlay(G.shared_sticker_eternal or (G.shared_stickers and G.shared_stickers.eternal)) end
    if a.perishable then overlay(G.shared_sticker_perishable or (G.shared_stickers and G.shared_stickers.perishable)) end
    if a.rental then overlay(G.shared_sticker_rental or (G.shared_stickers and G.shared_stickers.rental)) end
    for key, sprite in pairs(G.shared_stickers or {}) do -- stickers added by mods keep their flag in ability
        if a[key] == true and key ~= "eternal" and key ~= "perishable" and key ~= "rental" then overlay(sprite) end
    end
    local stake_sticker = card.sticker or (G.SETTINGS and G.SETTINGS.run_stake_stickers and card.sticker_run)
    if stake_sticker and stake_sticker ~= "NONE" and G.shared_stickers then overlay(G.shared_stickers[stake_sticker]) end
    return ov
end

emit_card = function(card, area_name)
    if SCN.emitted[card] then return end
    SCN.emitted[card] = true
    if card.states and card.states.visible == false then return end

    local a = card.ability or {}
    local center = card.config and card.config.center or {}
    local item = {
        k = "c", id = oid(card),
        f = card.facing or "front",
        set = a.set or "",
        key = center.key or "",
        name = a.name or "",
    }
    if area_name then item.area = area_name end
    if card.highlighted then item.hl = true end
    if card.debuff then item.db = true end
    if card.greyed then item.gr = true end -- already played (View Deck greys these out)
    if card.edition and card.edition.type then item.ed = card.edition.type end
    if card.seal then item.seal = card.seal end
    if card.base and card.base.value and (a.set == "Default" or a.set == "Enhanced") then
        item.rank, item.suit = card.base.value, card.base.suit
    end
    if card.cost then item.cost = num(card.cost) end
    if card.sell_cost then item.sell = num(card.sell_cost) end
    -- a tarot / planet / spectral card for sale that could be used right now: VR offers "buy and use"
    if area_name == "shop_jokers" and a.consumeable then
        local ok, usable = pcall(function() return card:can_use_consumeable() end)
        if ok and usable then item.cu = true end
    end
    local ch = card.children or {}
    -- (a sprite without a position - seen in some menus - is skipped; it used to break the whole
    -- scene, so a newly opened window never reached VR)
    local center_xy, front_xy, back_xy = sprite_xy(ch.center), sprite_xy(ch.front), sprite_xy(ch.back)
    if ch.center and ch.center.atlas and center_xy then -- (an AnimatedSprite in the Blinds collection)
        item.ca = ch.center.atlas.name
        item.cp = arr({ num(center_xy.x), num(center_xy.y) })
    end
    if ch.front and ch.front.atlas and front_xy and a.effect ~= "Stone Card" then -- stone cards hide rank and suit
        item.fa = ch.front.atlas.name
        item.fp = arr({ num(front_xy.x), num(front_xy.y) })
    end
    if ch.back and ch.back.atlas and back_xy then
        item.ba = ch.back.atlas.name
        item.bp = arr({ num(back_xy.x), num(back_xy.y) })
    end
    -- what the game draws on top of the card: its seal, then stickers (Eternal, Perishable, Rental,
    -- stake stickers, mod stickers) - each a sprite {a = atlas, p = {x, y}}
    if item.f == "front" then
        local ov = card_stickers(card)
        -- legendary jokers (Perkeo, Canio, ...), Hologram and The Soul: the face floats above the card
        -- as its own sprite (drawn first, under the stickers)
        if ch.floating_sprite and ch.floating_sprite.atlas and ch.floating_sprite.atlas.name and ch.floating_sprite.sprite_pos then
            table.insert(ov, 1, { a = ch.floating_sprite.atlas.name, p = arr({ num(ch.floating_sprite.sprite_pos.x), num(ch.floating_sprite.sprite_pos.y) }) })
        end
        if #ov > 0 then item.ov = ov end
    end
    if put_rect(item, card) then
        add(item)
        SCN.group_of[card] = SCN.group
        use_atlas(item.ca); use_atlas(item.fa); use_atlas(item.ba)
        for _, o in ipairs(item.ov or {}) do use_atlas(o.a) end
    end

    -- buttons attached to the card (buy, use, sell, price tag); the tooltip goes on top of everything.
    -- Inside a card row the buttons wait until all cards are drawn: the SELL tab sticks out to the
    -- right and would otherwise lie under the next card.
    for k, child in pairs(ch) do
        if is_a(child, UIBox) then
            if k == "h_popup" then queue_popup(child, card)
            elseif SCN.card_buttons then SCN.card_buttons[#SCN.card_buttons + 1] = child
            else emit_box(child) end
        end
    end
end

emit_area = function(area)
    if SCN.emitted[area] then return end
    SCN.emitted[area] = true
    local name = SCN.area_names[area] or "area"
    local info = {
        id = oid(area), name = name,
        type = area.config and area.config.type or "",
        n = area.cards and #area.cards or 0,
        lim = num(area.config and area.config.card_limit),
    }
    put_rect(info, area)
    SCN.areas[#SCN.areas + 1] = info
    if area.states and area.states.visible == false then return end
    -- Steamodded's run setup (decks, stakes, challenges, seed) shows its choices as little "deck"
    -- type stacks: each deck of the grid is a stack of its card backs (only the top one is sent),
    -- the chosen deck and the stake tower show every card
    local cfg = area.config or {}
    if info.type == "deck" and (cfg.run_select or cfg.run_select_deck_preview or cfg.run_select_stake_tower) then
        local cards = area.cards or {}
        if cfg.run_select and cards[#cards] then
            emit_card(cards[#cards], name)
        else
            for _, card in ipairs(cards) do emit_card(card, name) end
        end
        return
    end
    -- the draw pile's "View Deck" button and "52/52" counter: VR has the 3D deck stack for that
    if name == "deck" or info.type == "deck" then return end
    -- the hand's "8/8" counter: the cards are in the player's hand in VR, the counter adds nothing
    local skip_boxes = name == "hand"
    if skip_boxes then
        for _, card in ipairs(area.cards or {}) do emit_card(card, name) end
        return
    end
    -- the area's own boxes (card counter "2/5", the voucher slot's restock note ...) travel with it
    for _, child in pairs(area.children or {}) do
        if is_a(child, UIBox) then emit_box(child) end
    end
    -- deck and discard pile are only sent as counts; drawing 52 stacked cards adds nothing
    if name == "deck" or name == "discard" or info.type == "deck" or info.type == "discard" then return end
    local outer = SCN.card_buttons
    SCN.card_buttons = {}
    for _, card in ipairs(area.cards or {}) do emit_card(card, name) end
    local buttons = SCN.card_buttons
    SCN.card_buttons = outer
    for _, box in ipairs(buttons) do emit_box(box) end -- on top of every card of the row
end

local function mark_nested(e, nested)
    local cfg = e.config
    if cfg and cfg.object then
        nested[cfg.object] = true
        -- e.g. Jimbo (Card_Character): his speech bubble and button belong to him, not on their own
        if Card_Character and is_a(cfg.object, Card_Character) then
            for _, child in pairs(cfg.object.children or {}) do nested[child] = true end
        end
    end
    for _, child in pairs(e.children or {}) do
        if type(child) == "table" then
            if child.UIT then mark_nested(child, nested) else nested[child] = true end
        end
    end
end

local function build_scene()
    SCN = { items = arr(), areas = arr(), late = {}, emitted = {}, nested = {}, area_names = {}, roles = {}, group = 0,
            atlases = {}, group_of = {}, track_ids = false, idpath = {} }
    for _, n in ipairs(AREA_NAMES) do if G[n] then SCN.area_names[G[n]] = n end end
    for _, n in ipairs(BOX_ROLES) do if G[n] then SCN.roles[G[n]] = n end end

    -- anything that is drawn as part of another box/card must not also be drawn on its own
    for _, box in ipairs(G.I.UIBOX or {}) do
        for _, child in pairs(box.children or {}) do SCN.nested[child] = true end
        if box.UIRoot then mark_nested(box.UIRoot, SCN.nested) end
    end
    for _, card in ipairs(G.I.CARD or {}) do
        for _, child in pairs(card.children or {}) do SCN.nested[child] = true end
    end
    for _, area in ipairs(G.I.CARDAREA or {}) do
        for _, child in pairs(area.children or {}) do SCN.nested[child] = true end
    end

    local groups = arr()
    local function top_level(obj, role, fn, owner)
        SCN.group = oid(obj)
        local g = { id = SCN.group, role = role or "" }
        put_rect(g, obj)
        if owner then
            g.owner = oid(owner)                      -- card this tooltip belongs to
            g.owner_group = SCN.group_of[owner]       -- group that card was drawn in
        end
        groups[#groups + 1] = g
        SCN.track_ids = (role == "HUD")
        SCN.idpath = {}
        fn(obj)
        SCN.track_ids = false
    end

    -- 1) card areas on the table (hand, jokers, consumables, play, shop areas when not inside UI)
    for _, area in ipairs(G.I.CARDAREA or {}) do
        if not SCN.nested[area] then top_level(area, "area:" .. (SCN.area_names[area] or "area"), emit_area) end
    end
    -- the BALATRO title logo is a free sprite (no UIBox), drawn over the title card
    local logo = G.SPLASH_LOGO
    if logo and G.STAGE == G.STAGES.MAIN_MENU and not (logo.states and logo.states.visible == false) then
        top_level(logo, "logo", function(o) emit_object(o) end)
    end
    -- 2) regular UI boxes (HUD, buttons, shop, blind select, main menu, ...)
    local overlay = G.OVERLAY_MENU
    -- Play / Sort / Discard live on the VR controllers, so their button row is not mirrored
    for _, box in ipairs(G.I.UIBOX or {}) do
        if box ~= overlay and not SCN.nested[box] and not SCN.emitted[box] and SCN.roles[box] ~= "buttons" then
            top_level(box, SCN.roles[box], emit_box)
        end
    end
    -- 3) overlay menus (options, run setup, collection, game over, ...) above the rest
    local overlay_from = #SCN.items
    if overlay then top_level(overlay, "OVERLAY_MENU", emit_box) end
    -- 4) tooltips last so they are always on top (incl. free-floating popups/alerts from their own registries)
    for _, reg in ipairs({ G.I.POPUP or {}, G.I.ALERT or {} }) do
        for _, box in ipairs(reg) do
            if not SCN.nested[box] then
                -- a card tooltip aligns itself to its card - or, like the extra info boxes
                -- ("Eternal", "Wild Card", ...), to another tooltip of that card. Follow that
                -- chain to the card: it is the owner, so VR can put the tooltip next to the card
                -- wherever it is drawn (shop on the table, packs, ...)
                local owner, node = nil, box
                for _ = 1, 10 do
                    local cfg = node.config or {}
                    node = cfg.major or cfg.parent or (node.role and node.role.major) or node.UIBox
                    if type(node) ~= "table" then break end
                    if is_a(node, Card) then owner = node; break end
                end
                queue_popup(box, owner)
            end
        end
    end
    -- an extra info box ("Polychrome", "Eternal" ...) whose chain didn't reach the card: it belongs to
    -- the card whose tooltip is showing (only one card's tooltip is open at a time)
    local shown_owner = nil
    for _, e in ipairs(SCN.late) do
        if e.owner then shown_owner = e.owner; break end
    end
    if shown_owner then
        for _, e in ipairs(SCN.late) do
            if not e.owner and e.box and e.box.config and (e.box.config.major or e.box.config.parent) then e.owner = shown_owner end
        end
    end
    local i = 1
    while SCN.late[i] do
        local entry = SCN.late[i]
        if not SCN.emitted[entry.box] then top_level(entry.box, "popup", emit_box, entry.owner) end
        i = i + 1
    end

    return {
        room = { w = r2(G.ROOM and G.ROOM.T.w or 20), h = r2(G.ROOM and G.ROOM.T.h or 11.5) },
        state_name = state_name(G.STATE),
        overlay = overlay ~= nil,
        overlay_from = overlay_from,
        groups = groups,
        areas = SCN.areas,
        items = SCN.items,
    }
end

----------------------------------------------------------------------------
-- Texture atlases: each one is read from the local game install (or the mod that
-- added it) and sent once per connection, the first time a scene uses it.
----------------------------------------------------------------------------
local function atlas_file(name)
    for _, list in ipairs({ G.asset_atli or {}, G.animation_atli or {} }) do
        for _, a in ipairs(list) do
            if a.name == name then return a.path end
        end
    end
end

local function atlas_png(name)
    local atlas = (G.ASSET_ATLAS and G.ASSET_ATLAS[name]) or (G.ANIMATION_ATLAS and G.ANIMATION_ATLAS[name])
    if not atlas then return nil end
    if atlas.image_data then -- atlases added by mods: smods keeps the decoded image
        local ok, file = pcall(function() return atlas.image_data:encode("png") end)
        if ok and file then return file:getString(), atlas end
    end
    local path = atlas_file(name)
    local data = path and love.filesystem.read(path)
    return data, atlas
end

local function send_atlas(name)
    VR.sent_atlas[name] = true -- also when unreadable, so it is not retried every frame
    local png, atlas = atlas_png(name)
    if not png then
        log("texture atlas '" .. name .. "' not readable")
        return
    end
    send("atlas", encode({
        name = name,
        px = num(atlas.px), py = num(atlas.py),
        frames = num(atlas.frames),
        scale = num(G.SETTINGS.GRAPHICS.texture_scaling or 1),
        png = love.data.encode("string", "base64", png),
    }))
end

-- The game's font for the current language (m6x11plus for most, Noto for CJK), sent once per connection
local function send_font()
    VR.sent_font = true
    local file = G.LANG and G.LANG.font and G.LANG.font.file
    local data = file and love.filesystem.read(file)
    if not data then
        log("font '" .. tostring(file) .. "' not readable")
        return
    end
    send("font", encode({ file = file, data = love.data.encode("string", "base64", data) }))
end

-- Which atlas cells make real Balatro cards: every playing-card front, the plain card base and the
-- back of every deck. The VR client remembers them (and their atlases) on the player's PC and shows
-- them in its card swirl while Balatro boots next time - before this mod is even running.
local function send_intro_assets()
    VR.sent_intro = true
    local function ref(atlas, pos)
        if type(atlas) ~= "string" or type(pos) ~= "table" then return nil end
        VR.state_atlases[atlas] = true -- make sure that atlas is sent too
        return { atlas = atlas, pos = arr({ num(pos.x), num(pos.y) }) }
    end
    local backs, fronts = arr(), arr()
    for _, back in ipairs(G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back or {}) do
        local r = ref(back.atlas or "centers", back.pos)
        if r then backs[#backs + 1] = r end
    end
    local front_atlas = (G.SETTINGS and G.SETTINGS.colourblind_option) and "cards_2" or "cards_1"
    for _, card in pairs(G.P_CARDS or {}) do
        local r = ref(card.atlas or front_atlas, card.pos)
        if r then fronts[#fronts + 1] = r end
    end
    local base = G.P_CENTERS and G.P_CENTERS.c_base
    send("intro", encode({ backs = backs, fronts = fronts, base = base and ref(base.atlas or "centers", base.pos) or nil }))
end

local function send_missing_atlases()
    if not VR.sent_font then
        send_font()
        return -- one big transfer per tick
    end
    if not VR.sent_intro then
        send_intro_assets()
        return
    end
    for _, used in ipairs({ SCN and SCN.atlases or {}, VR.state_atlases or {} }) do
        for name in pairs(used) do
            if not VR.sent_atlas[name] then
                send_atlas(name)
                return -- one per tick keeps frame times smooth
            end
        end
    end
end

----------------------------------------------------------------------------
-- Semantic state (deck, round, jokers) for gestures and 3D props
----------------------------------------------------------------------------
-- copies the plain values (numbers, strings, booleans) of a table
local function plain_fields(t)
    local out = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "number" or tv == "string" or tv == "boolean" then out[k] = v
        elseif tv == "table" and v.to_number then out[k] = num(v) end
    end
    return out
end

-- The value a joker has collected so far, exactly as its tooltip shows it: the "(Currently +12 Mult)"
-- line of the game's own description, e.g. "+12 Mult", "X1.5 Mult", "+30 Chips". "" if it has none.
-- Built from the game's tooltip table every half second per joker (DynaTexts made for it are freed).
local joker_values = setmetatable({}, { __mode = "k" })

local function ui_text(node, out)
    if type(node) ~= "table" then return end
    local cfg = node.config
    if cfg and type(cfg.text) == "string" then out[#out + 1] = cfg.text end
    if cfg and type(cfg.object) == "table" then
        local o = cfg.object
        if type(o.strings) == "table" and o.strings[1] and type(o.strings[1].string) == "string" then
            out[#out + 1] = o.strings[1].string
        end
    end
    if type(node.nodes) == "table" then
        for _, c in ipairs(node.nodes) do ui_text(c, out) end
    end
end

-- The tooltip table holds live game objects (the joker's name is a floating DynaText, some texts
-- too). They register themselves with the game, which updates them every frame – so every one of
-- them must be removed again, or the game gets slower and slower.
local function free_ui(t, seen, depth)
    if type(t) ~= "table" or seen[t] or depth > 16 then return end
    seen[t] = true
    if t.T then -- a game object: only the tooltip's own texts go, never a card or anything else
        if DynaText and is_a(t, DynaText) and type(t.remove) == "function" then pcall(t.remove, t) end
        return
    end
    for _, v in pairs(t) do
        if type(v) == "table" then free_ui(v, seen, depth + 1) end
    end
end

-- Jokers whose changing value is not in a "(Currently ...)" line of their tooltip: read straight
-- from the card (by the joker's name, as the game itself does). `shown` is what the tooltip gave.
local function round_card() return G.GAME and G.GAME.current_round or {} end
-- (a face-down card in the hand - The House, The Wheel, The Mark, The Fish - must not be given away)
local function any_face_down(cards)
    for _, c in ipairs(cards or {}) do
        if c.facing == "back" then return true end
    end
    return false
end
local JOKER_LIVE = {
    ["Loyalty Card"] = function(c)
        local r = c.ability.loyalty_remaining
        if r == nil then return nil end
        return r == 0 and "Active!" or (r .. " remaining")
    end,
    ["Banner"] = function(c) -- +30 Chips per discard left
        local d = round_card().discards_left
        return d and ("+" .. (c.ability.extra * d) .. " Chips") or nil
    end,
    ["Raised Fist"] = function(c) -- double the lowest rank held in hand
        if not (G.hand and G.hand.cards and #G.hand.cards > 0) or any_face_down(G.hand.cards) then return nil end
        local m, id = 15, 15
        for _, h in ipairs(G.hand.cards) do
            if id >= h.base.id and h.ability.effect ~= "Stone Card" then m = h.base.nominal; id = h.base.id end
        end
        return id < 15 and ("+" .. (2 * m) .. " Mult") or nil
    end,
    ["Supernova"] = function(c) -- the selected poker hand's times played
        if not (G.hand and G.hand.highlighted and #G.hand.highlighted > 0) or any_face_down(G.hand.highlighted) then return nil end
        local text = G.FUNCS.get_poker_hand_info(G.hand.highlighted)
        local h = text and G.GAME.hands[text]
        return h and ("+" .. h.played .. " Mult") or nil
    end,
    ["Misprint"] = function(c)
        local e = c.ability.extra
        return type(e) == "table" and ("+" .. e.min .. " to +" .. e.max .. " Mult") or nil
    end,
    ["Egg"] = function(c) return "Sells for $" .. c.sell_cost end,
    ["Rocket"] = function(c) return "$" .. c.ability.extra.dollars .. " per round" end,
    ["Turtle Bean"] = function(c) return "+" .. c.ability.extra.h_size .. " hand size" end,
    ["Ice Cream"] = function(c) return "+" .. c.ability.extra.chips .. " Chips" end,
    ["Popcorn"] = function(c) return "+" .. c.ability.mult .. " Mult" end,
    ["Ramen"] = function(c) return "X" .. string.format("%.2f", c.ability.x_mult) .. " Mult" end,
    ["Seltzer"] = function(c) return c.ability.extra .. " hands left" end,
    -- the target changes every round: which suit / card / rank / hand it is now
    ["Ancient Joker"] = function(c)
        local s = round_card().ancient_card
        return s and s.suit and localize(s.suit, "suits_plural") or nil
    end,
    ["The Idol"] = function(c)
        local s = round_card().idol_card
        return s and s.rank and (localize(s.rank, "ranks") .. " of " .. localize(s.suit, "suits_plural")) or nil
    end,
    ["Mail-In Rebate"] = function(c)
        local s = round_card().mail_card
        return s and s.rank and localize(s.rank, "ranks") or nil
    end,
    ["To Do List"] = function(c)
        return c.ability.to_do_poker_hand and localize(c.ability.to_do_poker_hand, "poker_hands") or nil
    end,
    ["Castle"] = function(c, shown) -- its chips, and this round's suit
        local s = round_card().castle_card
        return s and s.suit and ((shown ~= "" and shown .. " - " or "") .. localize(s.suit, "suits_plural")) or nil
    end,
    ["Fortune Teller"] = function(c, shown) -- the tooltip says just "+12"
        return shown ~= "" and not shown:find("Mult") and (shown .. " Mult") or nil
    end,
}

local function joker_value(card)
    local now = love.timer.getTime()
    local cached = joker_values[card]
    if cached and now - cached.t < 1.0 then return cached.v end
    local value = ""
    local ok, t = pcall(card.generate_UIBox_ability_table, card)
    if ok and type(t) == "table" and type(t.main) == "table" then
        for _, line in ipairs(t.main) do
            local parts = {}
            if type(line) == "table" then for _, n in ipairs(line) do ui_text(n, parts) end end
            local s = table.concat(parts):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
            local inner = s:match("^%((.*)%)$")
            -- a number, and not a fixed hint like "(Must have room)", "(10, 8, 6, 4, 2)" or "(ex: ...)"
            if inner and inner:find("%d") and not inner:find("^ex:") and not inner:find("^[%dA, ]+$") then
                value = inner:gsub("^Currently ", ""):gsub("^ ", "")
            end
        end
    end
    if ok and type(t) == "table" then free_ui(t, {}, 0) end -- give back what the tooltip table created
    local live = card.ability and JOKER_LIVE[card.ability.name]
    if live then
        local ok2, v = pcall(live, card, value)
        if ok2 and type(v) == "string" and v ~= "" then value = v end
    end
    joker_values[card] = { t = now, v = value }
    return value
end

-- Generic joker data: the VR client's augmented jokers read what they need with small expressions,
-- e.g. ab["mult"], extra["chips"], target["suit"]. New jokers therefore need no mod change.
local function joker_state(card, slot)
    local a = card.ability or {}
    local cr = G.GAME.current_round or {}
    local j = {
        uid = oid(card), slot = slot, key = card.config.center.key, name = a.name or "",
        edition = card.edition and card.edition.type or "", debuffed = card.debuff and true or false,
        facing = card.facing or "front", -- "back": turned face down (The Amber Acorn) - VR hides what it is
        pinned = card.pinned and true or false, -- (challenges) stays the leftmost joker: VR shows a pin and keeps it there
        ab = {
            mult = num(a.mult),
            x_mult = num(a.x_mult),
            invis_rounds = num(a.invis_rounds),
            loyalty_remaining = num(a.loyalty_remaining),
            to_do = a.to_do_poker_hand or "",
        },
        -- the game stores either a table (chips, h_size, every, ...) or a single number in "extra"
        extra = type(a.extra) == "table" and plain_fields(a.extra) or { value = num(a.extra) },
        target = {},
        value = card.facing == "back" and "" or joker_value(card), -- "+12 Mult" ...: shown on the joker's pedestal in VR
        sell = num(card.sell_cost), -- the price sticker under the pedestal
        stickers = card_stickers(card), -- Eternal, Rental, ... shown as small badges on the 3D pedestal
    }
    -- Blueprint / Brainstorm: the game works out every frame whether the joker they copy can be
    -- copied ("compatible" / "incompatible"); VR shows it as a green tick or a red X sticker
    local key = card.config.center.key
    if key == "j_blueprint" or key == "j_brainstorm" then
        j.compat = a.blueprint_compat or ""
    end
    local n = a.name
    if n == "Castle" and cr.castle_card then
        j.target.suit = cr.castle_card.suit
    elseif n == "Mail-In Rebate" and cr.mail_card then
        j.target.rank = cr.mail_card.rank
    elseif n == "Ancient Joker" and cr.ancient_card then
        j.target.suit = cr.ancient_card.suit
    elseif n == "The Idol" and cr.idol_card then
        j.target.rank, j.target.suit = cr.idol_card.rank, cr.idol_card.suit
    end
    return j
end

local function deck_composition()
    local comp = { Spades = 0, Hearts = 0, Clubs = 0, Diamonds = 0, face = 0, aces = 0, numbered = 0 }
    if G.deck and G.deck.cards then
        for _, c in ipairs(G.deck.cards) do
            local b = c.base or {}
            if b.suit and comp[b.suit] then comp[b.suit] = comp[b.suit] + 1 end
            if b.id == 14 then comp.aces = comp.aces + 1
            elseif b.id and b.id >= 11 and b.id <= 13 then comp.face = comp.face + 1
            elseif b.id then comp.numbered = comp.numbered + 1 end
        end
    end
    return comp
end

VR.state_atlases = {}

-- {atlas, [x, y]} of a sprite for the 3D props; also schedules that atlas for sending
local function sprite_ref(atlas, pos)
    if type(atlas) ~= "string" or type(pos) ~= "table" then return nil end
    VR.state_atlases[atlas] = true
    return { atlas = atlas, pos = arr({ num(pos.x), num(pos.y) }) }
end

-- Poker hands above level 1: VR shows each as a planet orbiting the player
local function hand_levels(in_run)
    local out = arr()
    if not (in_run and G.GAME and G.GAME.hands) then return out end
    for name, h in pairs(G.GAME.hands) do
        if type(h) == "table" and h.visible ~= false and num(h.level) > 1 then
            out[#out + 1] = { name = name, level = num(h.level), played = num(h.played) }
        end
    end
    return out
end

-- Tarot / planet / spectral cards in the consumable slots, and whether they can be used right now
local function consumable_state(in_run)
    local out = arr()
    if not (in_run and G.consumeables and G.consumeables.cards) then return out end
    for i, c in ipairs(G.consumeables.cards) do
        local ok, usable = pcall(function() return c:can_use_consumeable() end)
        out[#out + 1] = { uid = oid(c), slot = i, set = c.ability and c.ability.set or "",
                          key = c.config and c.config.center and c.config.center.key or "",
                          can_use = (ok and usable) and true or false, sell = num(c.sell_cost),
                          can_sell = (c.can_sell_card and c:can_sell_card()) and true or false }
    end
    return out
end

-- Profile statistics for the casino's Hall of Fame / Hall of Shame (all runs of this profile)
-- Stats -> Card Stats: the game's bar chart of the most used jokers / consumables / vouchers. VR
-- builds it as columns standing around you in a half circle. The tab being shown is recorded when
-- the game builds it; the chart is gone as soon as another overlay opens or the menu closes.
VR.usage = nil
VR.usage_open = false
local SET_ATLAS = { Joker = "Joker", Tarot = "Tarot", Planet = "Tarot", Spectral = "Tarot", Voucher = "Voucher" }
local usage_ref = create_UIBox_usage
function create_UIBox_usage(args)
    local r = usage_ref(args)
    local ok, info = pcall(function()
        args = args or {}
        local kind, set = args[1], args[2]
        local list = {}
        for k, v in pairs(G.PROFILES[G.SETTINGS.profile][kind] or {}) do
            local c = G.P_CENTERS[k]
            if c and (not set or c.set == set) and c.discovered then list[#list + 1] = { key = k, count = v.count or 0, c = c } end
        end
        table.sort(list, function(a, b) return a.count > b.count end)
        local out = arr()
        for i = 1, math.min(10, #list) do
            local e = list[i]
            local col = (G.C.SECONDARY_SET and G.C.SECONDARY_SET[e.c.set]) or G.C.RED
            local ok_name, name = pcall(localize, { type = "name_text", set = e.c.set, key = e.key })
            out[#out + 1] = {
                key = e.key, count = num(e.count), set = e.c.set or "",
                name = ok_name and type(name) == "string" and name or (e.c.name or e.key),
                colour = arr({ num(col[1]), num(col[2]), num(col[3]) }),
                sprite = sprite_ref(e.c.atlas or SET_ATLAS[e.c.set] or "centers", e.c.pos),
            }
        end
        local titles = { joker_usage = "Jokers", consumeable_usage = "Consumables", Tarot = "Tarots", Planet = "Planets",
            Spectral = "Spectrals", Voucher = "Vouchers" }
        local tabs = arr()
        for _, k in ipairs({ "b_stat_jokers", "b_stat_consumables", "b_stat_tarots", "b_stat_planets", "b_stat_spectrals", "b_stat_vouchers" }) do
            tabs[#tabs + 1] = localize(k) -- (the tab buttons' labels: VR switches tabs with them)
        end
        return { title = titles[set or kind] or "", cards = out, tabs = tabs, current = titles[set or kind] or "" }
    end)
    if ok then VR.usage = info else log("card stats: " .. tostring(info)) end
    return r
end
local overlay_menu_ref = G.FUNCS.overlay_menu
G.FUNCS.overlay_menu = function(...)
    VR.usage_open = false -- (another overlay: the chart goes)
    return overlay_menu_ref(...)
end
local usage_open_ref = G.FUNCS.usage
G.FUNCS.usage = function(...)
    local r = usage_open_ref(...)
    VR.usage_open = true
    return r
end

local function profile_stats()
    local p = G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
    if not p then return nil end
    local hs = p.high_scores or {}
    local cs = p.career_stats or {}
    local function amt(k) return num(hs[k] and hs[k].amt) end
    local fav_hand, fav_hand_n = "", 0
    for _, v in pairs(p.hand_usage or {}) do
        if type(v) == "table" and num(v.count) > fav_hand_n then fav_hand, fav_hand_n = tostring(v.order or ""), num(v.count) end
    end
    local fav_joker, fav_joker_n = "", 0
    for key, v in pairs(p.joker_usage or {}) do
        if type(v) == "table" and num(v.count) > fav_joker_n then
            local c = G.P_CENTERS and G.P_CENTERS[key]
            fav_joker, fav_joker_n = c and c.name or tostring(key), num(v.count)
        end
    end
    return {
        -- best_hand -1 means "naneinf" (an infinite score)
        best_hand = (amt("hand") == math.huge or amt("hand") ~= amt("hand")) and -1 or amt("hand"),
        furthest_ante = amt("furthest_ante"), furthest_round = amt("furthest_round"),
        most_money = amt("most_money"), win_streak = amt("win_streak"), boss_streak = amt("boss_streak"),
        wins = num(cs.c_wins), losses = num(cs.c_losses), rounds = num(cs.c_rounds),
        discarded = num(cs.c_cards_discarded), rerolls = num(cs.c_shop_rerolls), jokers_sold = num(cs.c_jokers_sold),
        spent = num(cs.c_shop_dollars_spent), hands_played = num(cs.c_hands_played),
        fav_hand = fav_hand, fav_hand_n = fav_hand_n, fav_joker = fav_joker, fav_joker_n = fav_joker_n,
    }
end

local function can_reroll_now()
    if G.STATE ~= G.STATES.SHOP or not G.GAME or not G.GAME.current_round then return false end
    local cr = G.GAME.current_round
    if (cr.free_rerolls or 0) > 0 then return true end
    return ((G.GAME.dollars or 0) - (G.GAME.bankrupt_at or 0)) - (cr.reroll_cost or 0) >= 0
end

-- The text of a UI definition (rows become lines): the game's own deck / stake descriptions. Any
-- DynaText in it is freed right away (they would pile up otherwise).
local function definition_text(def)
    local lines = {}
    local function walk(n, line)
        if type(n) ~= "table" then return line end
        local cfg = n.config or {}
        if n.n == G.UIT.T and cfg.text then
            line = line .. tostring(cfg.text)
        elseif n.n == G.UIT.O and type(cfg.object) == "table" and cfg.object.strings then
            local s = cfg.object.strings[cfg.object.focused_string or 1]
            if s and s.string then line = line .. tostring(s.string) end
        end
        for _, c in ipairs(n.nodes or {}) do
            if type(c) == "table" and c.n == G.UIT.R then
                local sub = walk(c, "")
                if sub ~= "" then lines[#lines + 1] = sub end
            else
                line = walk(c, line)
            end
        end
        return line
    end
    local rest = walk(def, "")
    if rest ~= "" then lines[#lines + 1] = rest end
    free_ui(def, {}, 0)
    return table.concat(lines, "\n")
end

-- localize() description nodes: a list of lines, each a list of text nodes
local function loc_lines(nodes)
    local out = {}
    for _, line in ipairs(nodes or {}) do
        local s = ""
        for _, n in ipairs(line) do
            if type(n) == "table" and n.config and n.config.text then s = s .. tostring(n.config.text) end
            if type(n) == "table" and n.config and type(n.config.object) == "table" and n.config.object.strings then
                local d = n.config.object.strings[n.config.object.focused_string or 1]
                if d and d.string then s = s .. tostring(d.string) end
            end
        end
        if s ~= "" then out[#out + 1] = s end
    end
    free_ui(nodes, {}, 0)
    return table.concat(out, "\n")
end

-- The VR "New Run" table: every deck (name, description, back sprite, unlocked, highest stake that
-- may be played with it) and every stake (name, description, chip sprite). Built once per visit to
-- the main menu: the descriptions come from the game's own texts.
local function setup_info()
    local profile = G.PROFILES[G.SETTINGS.profile] or {}
    local all = profile.all_unlocked and true or false
    local stakes = arr()
    local stake_pool = G.P_CENTER_POOLS.Stake or {}
    for i, st in ipairs(stake_pool) do
        local nodes = {}
        pcall(localize, { type = 'descriptions', key = st.key, set = st.set, nodes = nodes })
        local ok_name, name = pcall(localize, { type = 'name_text', key = st.key, set = st.set })
        stakes[#stakes + 1] = { index = i, key = st.key, name = ok_name and name or st.key, text = loc_lines(nodes),
                                sprite = sprite_ref(st.atlas or "chips", st.pos) }
    end
    local decks = arr()
    for _, center in ipairs(G.P_CENTER_POOLS.Back or {}) do
        local unlocked = (center.unlocked or all) and true or false
        local ok_text, text = pcall(function() return definition_text(Back(center):generate_UI()) end)
        local ok_name, name = pcall(localize, { type = 'name_text', set = 'Back', key = center.key })
        local won = get_deck_win_stake(center.key) or 0
        decks[#decks + 1] = {
            key = center.key, name = (ok_name and unlocked) and name or "Locked Deck", unlocked = unlocked,
            text = ok_text and text or "", sprite = sprite_ref(center.atlas or "centers", center.pos), -- (VR greys locked ones)
            max_stake = all and #stake_pool or math.min(won + 1, #stake_pool),
        }
    end
    local memory = profile.MEMORY or {}
    local last_deck = "b_red"
    for _, center in ipairs(G.P_CENTER_POOLS.Back or {}) do
        if center.name == memory.deck then last_deck = center.key end
    end
    return { decks = decks, stakes = stakes, last_deck = last_deck, last_stake = num(memory.stake or 1),
             tutorial_done = G.SETTINGS.tutorial_complete and true or false }
end

-- The VR main menu: the saved run for the "Continue" stack (deck, ante, round) and the profile name.
-- The save file is read once per visit to the main menu (as the run setup screen does it).
-- A profile was (re)loaded - switched in the profile select, or its data wiped: the game builds its
-- cards' unlocks anew, so the saved run and the New Run table's decks are read again afterwards.
local init_item_prototypes_ref = Game.init_item_prototypes
function Game:init_item_prototypes(...)
    local r = init_item_prototypes_ref(self, ...)
    VR.menu_save_read = false
    return r
end

local function menu_info()
    -- (read again when the profile changed: switching profiles stays in the main menu)
    if VR.menu_save_read ~= true or VR.menu_profile ~= G.SETTINGS.profile then
        VR.menu_save_read = true
        VR.menu_profile = G.SETTINGS.profile
        local raw = get_compressed(G.SETTINGS.profile .. '/' .. 'save.jkr')
        VR.menu_save = raw and STR_UNPACK(raw) or nil
        local ok, info = pcall(setup_info)
        VR.menu_setup = ok and info or nil
        if not ok then log("new run table: " .. tostring(info)) end
    end
    local saved = nil
    local s = VR.menu_save
    if type(s) == "table" and type(s.GAME) == "table" and type(s.BACK) == "table" then
        local key = "b_red"
        for k, v in pairs(G.P_CENTERS) do
            if v.name == s.BACK.name and v.set == "Back" then key = k end
        end
        local c = G.P_CENTERS[key]
        local rr = s.GAME.round_resets or {}
        saved = {
            deck_key = key, deck_name = s.BACK.name or "",
            ante = num(rr.ante), round = num(s.GAME.round), dollars = num(s.GAME.dollars),
            sprite = c and sprite_ref(c.atlas or "centers", c.pos) or nil,
        }
    end
    local profile = G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
    return { saved = saved, profile = profile and profile.name or "", overlay = G.OVERLAY_MENU ~= nil, setup = VR.menu_setup }
end

-- Text boxes (the seed of a seeded run, a profile's name ...): the game updates each visible one
-- every frame through G.FUNCS.text_input. The last one seen is the one VR's keyboard types into.
local text_input_ref = G.FUNCS.text_input
G.FUNCS.text_input = function(e)
    VR.text_box, VR.text_box_t = e, love.timer.getTime()
    return text_input_ref(e)
end

local function text_input_state()
    local e = VR.text_box
    if not (e and VR.text_box_t and love.timer.getTime() - VR.text_box_t < 0.5) then return nil end
    local args = e.config and e.config.ref_table
    local t = args and args.text
    if not (t and t.ref_table) then return nil end
    return { text = tostring(t.ref_table[t.ref_value] or ""), hooked = G.CONTROLLER.text_input_hook == e,
             max = num(args.max_length or 16), extended = args.extended_corpus and true or false,
             caps = args.all_caps and true or false, prompt = tostring(args.prompt_text or "") }
end

-- The score flames behind chips and mult (strength and colours), while they burn
local function score_flame(names)
    local args = flame_args(names)
    local intensity = args and num(args.real_intensity or args.intensity) or 0
    if intensity <= 0.01 then return nil end
    return { i = r3(intensity), c = col(args.colour_1), c2 = col(args.colour_2) }
end

-- The boss rule as one line of text. The game keeps it in blind.loc_debuff_lines: plain strings in
-- vanilla, but newer Steamodded puts the parsed description there instead (per line a list of parts
-- {strings = {"text", {"1"} ...}}, where {"1"} stands for loc_debuff_lines.vars[1]).
local function blind_desc(blind)
    local lines = blind and blind.loc_debuff_lines
    if type(lines) ~= "table" then return "" end
    local vars = type(lines.vars) == "table" and lines.vars or {}
    local out = {}
    local function walk(t)
        if type(t) == "string" then out[#out + 1] = t; return end
        if type(t) ~= "table" then return end
        if type(t.strings) == "table" then -- one part of a parsed line
            for _, s in ipairs(t.strings) do
                if type(s) == "string" then
                    out[#out + 1] = s
                elseif type(s) == "table" and vars[tonumber(s[1]) or 0] ~= nil then
                    out[#out + 1] = tostring(vars[tonumber(s[1])])
                end
            end
            return
        end
        for _, c in ipairs(t) do walk(c) end
    end
    for _, line in ipairs(lines) do
        walk(line)
        out[#out + 1] = " "
    end
    return (table.concat(out):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function build_state()
    local game = G.GAME or {}
    local in_run = G.STAGE == G.STAGES.RUN
    local main_menu = G.STAGE == G.STAGES.MAIN_MENU
    if not main_menu then VR.menu_save_read = false end -- read the save again on the next visit
    -- the game builds its menu buttons a few seconds after the main menu starts (after the title
    -- animation) and slides them in: VR shows its menu table only once they are there and usable
    local ui = G.MAIN_MENU_UI
    if not main_menu or not ui or ui.REMOVED then
        VR.menu_ready = false
    elseif not VR.menu_ready and ui.VT and ui.T and math.abs(ui.VT.y - ui.T.y) < 0.1 then
        VR.menu_ready = true
    end
    local cr = game.current_round or {}
    -- in a run the chosen deck is selected_back; on the run setup screen the deck being looked at is viewed_back
    local back = game.selected_back or (not in_run and game.viewed_back) or nil
    local blind = game.blind
    local back_center = back and back.effect and back.effect.center
    local stake = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake and G.P_CENTER_POOLS.Stake[game.stake or 1]
    local blind_center = blind and blind.config and blind.config.blind
    local jokers = arr()
    if in_run and G.jokers then
        for i, c in ipairs(G.jokers.cards) do jokers[#jokers + 1] = joker_state(c, i) end
    end
    return {
        state = G.STATE or 0,
        state_name = state_name(G.STATE),
        in_run = in_run,
        won = (in_run and game.won) and true or false, -- set by win_game() after the Ante 8 boss
        deck = {
            back_name = back and back.name or "",
            back_key = back_center and back_center.key or "",
            back_sprite = back_center and sprite_ref(back_center.atlas or "centers", back_center.pos),
            remaining = (G.deck and G.deck.cards) and #G.deck.cards or 0,
            total = G.playing_cards and #G.playing_cards or 0,
            composition = deck_composition(),
        },
        overlay = G.OVERLAY_MENU ~= nil,
        menu = (main_menu and VR.menu_ready) and menu_info() or nil, -- only in the main menu (once it is usable): the VR menu on the table
        viewing_deck = VR.deck_view_open and G.OVERLAY_MENU ~= nil or false,
        round = {
            ante = num(game.round_resets and game.round_resets.ante),
            round = num(game.round),
            hands_left = num(cr.hands_left),
            discards_left = num(cr.discards_left),
            chips = num(game.chips),
            dollars = num(game.dollars),
            run_chips = in_run and num(game.vr_run_chips) or 0, -- every round's score of this run added up
            -- the poker hand of the selected cards, as the run panel shows it ("Flush", " Lvl.3", chips x mult)
            hand = cr.current_hand and {
                name = tostring(cr.current_hand.handname or ""),
                level = tostring(cr.current_hand.hand_level or ""),
                chips = tostring(cr.current_hand.chip_text or ""),
                mult = tostring(cr.current_hand.mult_text or ""),
                cf = score_flame(FLAMES.flame_chips), mf = score_flame(FLAMES.flame_mult), -- (VR: flames over the play stand)
            } or nil,
        },
        blind = {
            name = blind and blind.name or "",
            key = blind and blind.config and blind.config.blind and blind.config.blind.key or "",
            chips = num(blind and blind.chips),
            boss = (blind and blind.boss) and true or false,
            -- the boss rule as the game words it ("Cards played previously this Ante are debuffed")
            colour = blind_center and blind_center.boss_colour and col(blind_center.boss_colour) or nil, -- the chip colour: VR tints the room
            -- (never lets the whole state fail: an unexpected text format only loses the rule)
            desc = (function() local ok, d = pcall(blind_desc, blind); return ok and d or "" end)(),
            sprite = blind_center and sprite_ref(blind_center.atlas or "blind_chips", { x = 0, y = blind_center.pos and blind_center.pos.y or 0 }),
        },
        -- the animated SHOP sign; VR shows it next to the shop instead of the game's sign box
        shop_sign = G.STATE == G.STATES.SHOP and G.ANIMATION_ATLAS and G.ANIMATION_ATLAS.shop_sign and {
            atlas = "shop_sign", frames = num(G.ANIMATION_ATLAS.shop_sign.frames),
            ref = sprite_ref("shop_sign", { x = 0, y = 0 }),
        } or nil,
        stake = num(game.stake),
        stake_name = stake and (stake.name or stake.key) or "",
        stake_sprite = stake and sprite_ref(stake.atlas or "chips", stake.pos),
        jokers = jokers,
        hand_levels = hand_levels(in_run),
        consumables = consumable_state(in_run),
        shop_open = G.STATE == G.STATES.SHOP,
        reroll_cost = num(cr.reroll_cost),
        can_reroll = can_reroll_now(),
        pack_waiting = VR.pending_pack ~= nil,
        blind_on_deck = in_run and tostring(game.blind_on_deck or "") or "",
        stats = (function() local ok, s = pcall(profile_stats); return ok and s or nil end)(),
        card_stats = (VR.usage_open and G.OVERLAY_MENU and VR.usage) or nil, -- the Card Stats chart (VR: columns around you)
        text_input = text_input_state(), -- a seed / profile name box on screen: VR shows its keyboard
    }
end

----------------------------------------------------------------------------
-- Commands from VR
----------------------------------------------------------------------------
local function input_blocked()
    local c = G.CONTROLLER
    if not c then return true end
    return ((c.locked and not (G.SETTINGS and G.SETTINGS.paused)) or (c.locks and c.locks.frame)) and true or false
end

-- box: the UIBox the button lives in (default: the hand's Play / Discard buttons)
local function click_ui_button(id, box)
    box = box or G.buttons
    local btn = box and box:get_UIE_by_ID(id)
    if btn and btn.config and btn.config.button and not btn.disable_button then
        btn:click()
        return true
    end
    return false
end

local function gamepad(button, pressed)
    local pad = G.CONTROLLER and G.CONTROLLER.keyboard_controller
    if not pad then return false end
    if pressed then love.gamepadpressed(pad, button) else love.gamepadreleased(pad, button) end
    return true
end

-- gated = must wait until the game accepts input (same rule as the real controller)
local HANDLERS = {
    ping = { gated = false, fn = function() return true end },

    -- the VR client's own settings the Options menu shows ("calm": Calm Lights on/off)
    vr_flags = { gated = false, fn = function(m)
        VR.calm_lights = (m.calm == true or m.calm == "true")
        if m.hands ~= nil then VR.hands = (m.hands == true or m.hands == "true") end
        if type(m.spec) == "string" then VR.spectator = m.spec end
        if m.amb ~= nil then VR.ambience = (m.amb == true or m.amb == "true") end
        if m.jimbo ~= nil then VR.jimbo = (m.jimbo == true or m.jimbo == "true") end
        if m.floor ~= nil then VR.floor.cm = num(m.floor) end
        if type(m.wheel) == "string" then VR.wheel_mode = m.wheel end
        return true
    end },

    click = { gated = true, fn = function(m)
        local o = objs[m.target or -1]
        if not o then return false end
        if is_a(o, Card) then o:click(); return true end
        if o.click and o.config and (o.config.button or o.config.button_UIE) then o:click(); return true end
        return false
    end },

    hover = { gated = false, fn = function(m)
        local o = objs[m.target or -1]
        if not o or not o.hover then return false end
        if o.states and o.states.hover then o.states.hover.is = true end
        o:hover()
        return true
    end },

    unhover = { gated = false, fn = function(m)
        local o = objs[m.target or -1]
        if not o or not o.stop_hover then return false end
        if o.states and o.states.hover then o.states.hover.is = false end
        o:stop_hover()
        return true
    end },

    play = { gated = true, fn = function()
        return G.STATE == G.STATES.SELECTING_HAND and click_ui_button("play_button")
    end },

    discard = { gated = true, fn = function()
        return G.STATE == G.STATES.SELECTING_HAND and click_ui_button("discard_button")
    end },

    -- the hand's "Rank" / "Suit" sort buttons (thumbstick click in VR). by = "rank", "suit" or
    -- "toggle" (the other order than the hand has now; G.hand remembers it in config.sort)
    sort = { gated = true, fn = function(m)
        if G.STAGE ~= G.STAGES.RUN or not (G.hand and G.hand.cards and #G.hand.cards > 0) then return false end
        local by = m.by
        if by == "toggle" then by = (G.hand.config.sort == "suit desc") and "rank" or "suit" end
        if by == "suit" then G.FUNCS.sort_hand_suit() else G.FUNCS.sort_hand_value() end
        return true
    end },

    -- "View Deck" while the VR hand is over the 3D deck. Only closes the overlay it opened itself,
    -- so it never closes options or other menus the player opened.
    deck_view = { gated = true, fn = function(m)
        if m.on ~= false then
            if G.OVERLAY_MENU or G.STAGE ~= G.STAGES.RUN or not G.deck then return false end
            G.FUNCS.deck_info()
            VR.deck_view_open = G.OVERLAY_MENU
            return true
        end
        local open = VR.deck_view_open
        VR.deck_view_open = nil
        if open and G.OVERLAY_MENU == open then
            G.FUNCS.exit_overlay_menu()
            return true
        end
        return false
    end },

    -- Reorder: put card `target` where card `to` is (same area; only hand and jokers, like dragging
    -- with the mouse). CardArea:align_cards lays cards out by list order every frame, so it sticks.
    move = { gated = true, fn = function(m)
        local card, other = objs[m.target or -1], objs[m.to or -1]
        if not (is_a(card, Card) and is_a(other, Card)) then return false end
        local area = card.area
        if not area or area ~= other.area then return false end
        local kind = area.config and area.config.type
        if kind ~= "hand" and kind ~= "joker" then return false end
        if card.states and card.states.drag and card.states.drag.can == false then return false end
        local from_i, to_i
        for i, c in ipairs(area.cards) do
            if c == card then from_i = i end
            if c == other then to_i = i end
        end
        if not from_i or not to_i or from_i == to_i then return false end
        table.remove(area.cards, from_i)
        table.insert(area.cards, to_i, card)
        area:set_ranks()
        card:juice_up(0.1, 0.1)
        pcall(play_sound, "cardSlide1")
        return true
    end },

    -- The VR joker board decides the order: ids = "uid;uid;..." from left to right. Only applied
    -- when it names exactly the jokers that are there.
    order = { gated = true, fn = function(m)
        local area = G.jokers
        if not (area and area.cards) or type(m.ids) ~= "string" then return false end
        local wanted, seen = {}, {}
        for id in m.ids:gmatch("%d+") do
            local card = objs[tonumber(id)]
            if not is_a(card, Card) or card.area ~= area or seen[card] then return false end
            seen[card] = true
            wanted[#wanted + 1] = card
        end
        if #wanted ~= #area.cards then return false end
        -- pinned jokers stay at the very left, in their own order (as the game's CardArea keeps them)
        local pinned, rest = {}, {}
        for _, card in ipairs(wanted) do
            if card.pinned then pinned[#pinned + 1] = card else rest[#rest + 1] = card end
        end
        table.sort(pinned, function(a, b) return (a.sort_id or 0) < (b.sort_id or 0) end)
        wanted = {}
        for _, card in ipairs(pinned) do wanted[#wanted + 1] = card end
        for _, card in ipairs(rest) do wanted[#wanted + 1] = card end
        for i, card in ipairs(wanted) do area.cards[i] = card end
        area:set_ranks()
        pcall(play_sound, "cardSlide1")
        return true
    end },

    -- index is 1-based into G.hand.cards
    highlight = { gated = true, fn = function(m)
        local card = G.hand and G.hand.cards and G.hand.cards[m.index or 0]
        if not card then return false end
        if m.on == false then G.hand:remove_from_highlighted(card)
        elseif not card.highlighted then G.hand:add_to_highlighted(card) end
        return true
    end },

    -- Gamepad emulation: LÖVE button names (a, b, x, y, dpup, leftshoulder, triggerleft, start, ...)
    button = { gated = false, fn = function(m)
        if not m.button then return false end
        if m.action == "press" then return gamepad(m.button, true)
        elseif m.action == "release" then return gamepad(m.button, false) end
        VR.pending_releases[#VR.pending_releases + 1] = m.button
        return gamepad(m.button, true)
    end },
}

local function ack(msg, ok)
    send("ack", encode({ cmd = msg.cmd or "", id = msg.id or 0, ok = ok and true or false }))
end

local function run_command(msg)
    local h = HANDLERS[msg.cmd or ""]
    if not h then ack(msg, false); return end
    local ok, result = pcall(h.fn, msg)
    if not ok then log("command '" .. tostring(msg.cmd) .. "' failed: " .. tostring(result)) end
    ack(msg, ok and result)
end

local function on_line(line)
    local msg = decode_flat(line)
    local h = HANDLERS[msg.cmd or ""]
    if h and h.gated then
        msg._t = love.timer.getTime()
        VR.queue[#VR.queue + 1] = msg
    else
        run_command(msg)
    end
end

local function process_queue(now)
    for _, b in ipairs(VR.pending_releases) do gamepad(b, false) end
    VR.pending_releases = {}

    -- drop stale commands, then run at most one gated command per frame (like one real click)
    while VR.queue[1] and now - VR.queue[1]._t > CFG.command_timeout do
        ack(table.remove(VR.queue, 1), false)
    end
    if VR.queue[1] and not input_blocked() then
        run_command(table.remove(VR.queue, 1))
    end
end

----------------------------------------------------------------------------
-- Main loop hook
----------------------------------------------------------------------------
local function report(where, err)
    local msg = where .. ": " .. tostring(err)
    if msg ~= VR.last_error then log(msg) end
    VR.last_error = msg
end

local function publish(now)
    if now - VR.last_scene_send >= CFG.scene_interval then
        VR.last_scene_send = now
        local ok, scene = pcall(build_scene)
        if ok then
            local payload = encode(scene)
            if payload ~= VR.last_scene or now - VR.last_scene_time > CFG.heartbeat_interval then
                send("scene", payload)
                VR.last_scene, VR.last_scene_time = payload, now
            end
            local ok_atlas, err = pcall(send_missing_atlases)
            if not ok_atlas then report("atlas", err) end
        else
            report("scene", scene)
        end
    end

    if now - VR.last_state_send >= CFG.state_interval then
        VR.last_state_send = now
        local ok, state = pcall(build_state)
        if ok then
            local payload = encode(state)
            if payload ~= VR.last_state or now - VR.last_state_time > CFG.heartbeat_interval then
                send("state", payload)
                VR.last_state, VR.last_state_time = payload, now
            end
        else
            report("state", state)
        end
    end
end

-- With "QUIT VR" the main menu row is wider and would run into the profile box at the bottom
-- left: while VR is connected the profile box moves up above the row.
local PROFILE_LIFT = -2.2
local function place_profile_button()
    local box = G.PROFILE_BUTTON
    if not (box and box.alignment and box.alignment.offset) then return end
    local want = (NET.state == "connected" and G.STAGE == G.STAGES.MAIN_MENU) and PROFILE_LIFT or 0
    if box.alignment.offset.y ~= want then
        box.alignment.offset.y = want
        box:align_to_major()
    end
end

-- All chips scored in this run (every round's score added up) for the casino's chip mountain.
-- Kept in G.GAME, so it is saved with the run and survives "Continue".
local function track_run_chips()
    local game = G.GAME
    if not (game and G.STAGE == G.STAGES.RUN) then return end
    local chips = num(game.chips)
    local last = game.vr_last_chips or 0
    if chips > last then game.vr_run_chips = (game.vr_run_chips or 0) + (chips - last) end
    game.vr_last_chips = chips -- a new round starts at 0 again
end

local game_update_ref = Game.update
function Game:update(dt)
    game_update_ref(self, dt)
    pcall(place_profile_button)
    pcall(track_run_chips)
    if VR.send_ambient_sounds then pcall(VR.send_ambient_sounds) end
    if VR.check_pending_pack then pcall(VR.check_pending_pack) end

    local now = love.timer.getTime()
    local ok, err = pcall(function()
        if not net_update_connection(now) then return end
        net_receive(on_line)
        process_queue(now)
        publish(now)
        net_flush()
    end)
    if not ok then report("update", err) end
end

-- The discards column of the run panel has no id in vanilla (hands has 'hud_hands'); give it one so
-- the VR client can hide hands + discards in its compact panel outside of rounds.
local function tag_discards_column(node)
    if type(node) ~= "table" then return false end
    local found = node.config and node.config.id == "discard_UI_count"
    for _, child in ipairs(node.nodes or {}) do
        if tag_discards_column(child) then found = true end
    end
    -- the column box itself: the 1.45-wide panel that contains the discard counter
    if found and node.config and node.config.minw == 1.45 and node.config.id == nil then
        node.config.id = "hud_discards"
    end
    return found
end

local create_hud_ref = create_UIBox_HUD
function create_UIBox_HUD()
    local def = create_hud_ref()
    pcall(tag_discards_column, def)
    return def
end

-- "Adjust VR Layout" button in the game's Options menu (only while a VR client is connected).
-- It tells the client to enter its calibration mode, where panels can be moved, rotated and resized.
G.FUNCS.vr_calibrate = function(e)
    G.FUNCS.exit_overlay_menu()
    VR.send_event("calibrate", {})
end

-- "VR: Switch Hands": swaps the hand that holds the cards and the pointing hand (left-handed mode)
G.FUNCS.vr_toggle_hand = function(e)
    G.FUNCS.exit_overlay_menu()
    VR.send_event("toggle_handedness", {})
end

-- "VR: Calm Lights": no flashes, flicker or pulsing light in VR (photosensitive players). The VR
-- client keeps the setting and tells it here (vr_flags), so the button shows the current state.
VR.calm_lights = false
VR.hands = true -- "VR: Hands": Jimbo's gloves in VR
VR.jimbo = true -- "VR: Jimbo": Jimbo at the casino table
VR.ambience = true -- "VR: Casino Sounds": slot machines, glasses, chips in the VR casino
VR.wheel_mode = "Real" -- "VR: Wheel of Fortune": Off / Deterministic / Real (see Card:use_consumeable)
VR.spectator = "Off" -- "VR: Spectator": the spectator camera window on the PC (Off / Eyes / Shoulder / Room)
G.FUNCS.vr_show_tips = function(e) -- "VR: How To Play": Jimbo's tips in VR again
    G.FUNCS.exit_overlay_menu()
    VR.send_event("show_tutorial", {})
end
-- "VR Settings" (in Options): the VR client's switches in one sub-menu, so Options stays short
local function vr_settings_box()
    local function b(label, button) return UIBox_button({ label = { label }, button = button, minw = 5, colour = G.C.GREEN }) end
    return create_UIBox_generic_options({ back_func = "options", contents = {
        b("VR: Switch Hands", "vr_toggle_hand"),
        b("VR: Calm Lights: " .. (VR.calm_lights and "On" or "Off"), "vr_toggle_calm"),
        b("VR: Hands: " .. (VR.hands and "On" or "Off"), "vr_toggle_hands"),
        b("VR: Jimbo: " .. (VR.jimbo and "On" or "Off"), "vr_toggle_jimbo"),
        b("VR: Casino Sounds: " .. (VR.ambience and "On" or "Off"), "vr_toggle_ambience"),
        b("VR: Spectator: " .. tostring(VR.spectator), "vr_cycle_spectator"),
        b("VR: Wheel of Fortune: " .. tostring(VR.wheel_mode), "vr_cycle_wheel"),
        b("VR: How To Play", "vr_show_tips"),
        -- the casino floor up or down (cm), when you seem to float or sink in the virtual casino
        create_slider({ label = "VR: Casino Floor Height (cm)", w = 5, h = 0.4, ref_table = VR.floor, ref_value = "cm",
                        min = -60, max = 60, callback = "vr_floor_changed" }),
    } })
end

-- the floor slider: every change goes to the VR client at once (it saves it for sitting / standing)
G.FUNCS.vr_floor_changed = function(rt)
    VR.send_event("floor_height", { cm = num(rt.ref_table[rt.ref_value]) })
end

G.FUNCS.vr_settings = function(e)
    G.SETTINGS.paused = true
    G.FUNCS.overlay_menu({ definition = vr_settings_box() })
end

-- a switch was flipped: the VR client answers with its new settings (vr_flags) – then the menu is
-- drawn again so the button shows the new state
local function refresh_vr_settings()
    G.E_MANAGER:add_event(Event({ trigger = "after", delay = 0.3, timer = "REAL", blockable = false, blocking = false,
        func = function()
            if G.OVERLAY_MENU then G.FUNCS.vr_settings() end
            return true
        end }))
end

G.FUNCS.vr_cycle_spectator = function(e)
    VR.send_event("cycle_spectator", {})
    refresh_vr_settings()
end
G.FUNCS.vr_toggle_ambience = function(e)
    VR.send_event("toggle_ambience", {})
    refresh_vr_settings()
end
G.FUNCS.vr_toggle_jimbo = function(e)
    VR.send_event("toggle_jimbo", {})
    refresh_vr_settings()
end
G.FUNCS.vr_toggle_hands = function(e)
    VR.send_event("toggle_hands", {})
    refresh_vr_settings()
end
G.FUNCS.vr_cycle_wheel = function(e)
    VR.send_event("cycle_wheel", {})
    refresh_vr_settings()
end
G.FUNCS.vr_toggle_calm = function(e)
    VR.send_event("toggle_calm", {})
    refresh_vr_settings()
end

-- Test money (see TEST_MONEY at the top)
local function give_test_money()
    if not TEST_MONEY or G.STAGE ~= G.STAGES.RUN or not G.GAME then return end
    ease_dollars(TEST_MONEY_AMOUNT)
end

G.FUNCS.vr_test_money = function(e)
    G.FUNCS.exit_overlay_menu()
    give_test_money()
end

-- Extreme mode for testing (also only with TEST_MONEY): each press gives the run more room, like
-- vouchers would - hand size, joker slots and consumable slots (F9 or "Test: Extreme" in Options)
local TEST_EXTREME = { hand = 3, jokers = 3, consumables = 2 }
local function give_test_extreme()
    if not TEST_MONEY or G.STAGE ~= G.STAGES.RUN or not G.GAME then return end
    if G.hand then G.hand:change_size(TEST_EXTREME.hand) end -- (draws the extra cards in a round)
    if G.jokers then G.jokers.config.card_limit = G.jokers.config.card_limit + TEST_EXTREME.jokers end
    if G.consumeables then G.consumeables.config.card_limit = G.consumeables.config.card_limit + TEST_EXTREME.consumables end
    log(("test extreme: hand +%d, jokers %d, consumables %d"):format(TEST_EXTREME.hand, -- (the hand grows a moment later)
        G.jokers and G.jokers.config.card_limit or 0, G.consumeables and G.consumeables.config.card_limit or 0))
end

G.FUNCS.vr_test_extreme = function(e)
    G.FUNCS.exit_overlay_menu()
    give_test_extreme()
end

local keypressed_ref = love.keypressed
function love.keypressed(key, ...)
    if key == "f8" then give_test_money() end
    if key == "f9" then give_test_extreme() end
    if keypressed_ref then return keypressed_ref(key, ...) end
end

local create_options_ref = create_UIBox_options
function create_UIBox_options()
    if NET.state ~= "connected" then return create_options_ref() end
    local generic_ref = create_UIBox_generic_options
    create_UIBox_generic_options = function(args)
        create_UIBox_generic_options = generic_ref
        if args and type(args.contents) == "table" then
            -- the vanilla list has nil holes (seed row etc.); rebuild it in order with our button after "Settings"
            local list = {}
            for i = 1, 20 do
                if args.contents[i] ~= nil then list[#list + 1] = args.contents[i] end
                if i == 1 then
                    list[#list + 1] = UIBox_button({ label = { "Adjust VR Layout" }, button = "vr_calibrate", minw = 5, colour = G.C.GREEN })
                    list[#list + 1] = UIBox_button({ label = { "VR Settings" }, button = "vr_settings", minw = 5, colour = G.C.GREEN })
                    if TEST_MONEY and G.STAGE == G.STAGES.RUN then
                        list[#list + 1] = UIBox_button({ label = { "Test: +$" .. TEST_MONEY_AMOUNT }, button = "vr_test_money", minw = 5, colour = G.C.MONEY or G.C.GOLD })
                        list[#list + 1] = UIBox_button({ label = { ("Test: Extreme (+%d Hand, +%d Jokers)"):format(TEST_EXTREME.hand, TEST_EXTREME.jokers) },
                            button = "vr_test_extreme", minw = 5, colour = G.C.PURPLE or G.C.RED })
                    end
                end
            end
            args.contents = list
        end
        return generic_ref(args)
    end
    local ok, result = pcall(create_options_ref)
    create_UIBox_generic_options = generic_ref
    if not ok then error(result) end
    return result
end

-- Settings in VR: only what changes something in VR. Gone: play/discard position (on the
-- controllers in VR), rumble (VR vibrates by itself), screenshake, shadows, CRT and bloom (2D
-- effects) and the whole Video tab (the desktop window). Pixel smoothing (the texture size VR gets)
-- moves to the Game tab, so there are two tabs: Game and Audio. Without VR: the game's own menu.
local function vr_settings_game_tab()
    return { n = G.UIT.ROOT, config = { align = "cm", padding = 0.05, colour = G.C.CLEAR }, nodes = {
        create_option_cycle({ label = localize('b_set_gamespeed'), scale = 0.8, options = { 0.5, 1, 2, 4 }, opt_callback = 'change_gamespeed',
            current_option = (G.SETTINGS.GAMESPEED == 0.5 and 1 or G.SETTINGS.GAMESPEED == 4 and 4 or G.SETTINGS.GAMESPEED + 1) }),
        create_toggle({ label = localize('ph_display_stickers'), ref_table = G.SETTINGS, ref_value = 'run_stake_stickers' }),
        create_toggle({ label = localize('b_high_contrast_cards'), ref_table = G.SETTINGS, ref_value = 'colourblind_option', callback = G.FUNCS.refresh_contrast_mode }),
        create_toggle({ label = localize('b_reduced_motion'), ref_table = G.SETTINGS, ref_value = 'reduced_motion' }),
        create_option_cycle({ w = 4, scale = 0.8, label = localize("b_set_pixel_smoothing"), options = localize('ml_smoothing_opt'),
            opt_callback = 'change_pixel_smoothing', current_option = G.SETTINGS.GRAPHICS.texture_scaling }),
        G.F_CRASH_REPORTS and create_toggle({ label = localize('b_set_crash_reports'), ref_table = G.SETTINGS, ref_value = 'crashreports',
            info = localize('ml_crash_report_info') }) or nil,
    } }
end

local create_settings_ref = create_UIBox_settings
function create_UIBox_settings(...)
    if NET.state ~= "connected" then return create_settings_ref(...) end
    local tabs = {
        { label = localize('b_set_game'), chosen = true, tab_definition_function = vr_settings_game_tab },
        { label = localize('b_set_audio'), tab_definition_function = G.UIDEF.settings_tab, tab_definition_function_args = 'Audio' },
    }
    return create_UIBox_generic_options({ back_func = 'options', contents = {
        create_tabs({ tabs = tabs, tab_h = 7.05, tab_alignment = 'tm', snap_to_nav = true }),
    } })
end

-- Main menu: a YouTube button (the mod author's channel) instead of the Discord / X icons
local YOUTUBE_URL = "https://www.youtube.com/@UnderTheVRadar"

G.FUNCS.vr_go_to_youtube = function(e)
    love.system.openURL(YOUTUBE_URL)
end

-- The VR client asks for texture atlases it needs on its own (Solatro: the playing cards and the
-- joker card while the game itself only shows its main menu)
-- The client asks for atlases it needs (e.g. Solatro's cards and joker): names separated by spaces,
-- because commands arrive as flat objects (decode_flat reads no lists).
HANDLERS.need_atlas = { gated = false, fn = function(m)
    local names = {}
    if type(m.names) == "string" then
        for name in m.names:gmatch("%S+") do names[#names + 1] = name end
    elseif type(m.names) == "table" then
        names = m.names
    end
    for _, name in ipairs(names) do
        if type(name) == "string" and ((G.ASSET_ATLAS and G.ASSET_ATLAS[name]) or (G.ANIMATION_ATLAS and G.ANIMATION_ATLAS[name])) then
            VR.state_atlases[name] = true
        end
    end
    return true
end }

-- A slider (volume, ...) moved with the VR beam: the client sends where on the track the beam is
-- (frac 0..1); the value is set like G.FUNCS.slider does it while the mouse drags.
HANDLERS.slider = { gated = false, fn = function(m)
    local e = objs[m.target or -1]
    if not (type(e) == "table" and e.config and e.config.func == "slider" and e.children and e.children[1]) then return false end
    local c = e.children[1]
    local rt = c.config and c.config.ref_table
    if not (rt and rt.ref_table and rt.ref_value) then return false end
    local f = math.max(0, math.min(1, tonumber(m.frac) or 0))
    rt.ref_table[rt.ref_value] = rt.min + (rt.max - rt.min) * f
    rt.text = string.format("%." .. tostring(rt.decimal_places or 0) .. "f", rt.ref_table[rt.ref_value])
    c.T.w = f * rt.w
    c.config.w = c.T.w
    if rt.callback then G.FUNCS[rt.callback](rt) end
    return true
end }

-- The VR main menu on the casino table: the buzzer (Play), the saved run's stack (Continue), the
-- album (Collection), the bell (Options), the YouTube sign and "QUIT VR AND GAME" (quits Balatro;
-- "QUIT ONLY VR" is the client's own business). They do what the game's own buttons do.
HANDLERS.menu = { gated = true, fn = function(m)
    if G.STAGE ~= G.STAGES.MAIN_MENU then return false end
    local action = m.action
    if action == "quit_game" then
        love.event.quit()
        return true
    elseif action == "youtube" then
        love.system.openURL(YOUTUBE_URL)
        return true
    end
    if G.OVERLAY_MENU then return false end -- another menu is open: close it first
    if action == "play" then
        return click_ui_button("main_menu_play", G.MAIN_MENU_UI) -- (run setup, or the tutorial the first time)
    elseif action == "continue" then
        if not G.SAVED_GAME then
            local raw = get_compressed(G.SETTINGS.profile .. '/' .. 'save.jkr')
            G.SAVED_GAME = raw and STR_UNPACK(raw) or nil
        end
        if not G.SAVED_GAME then return false end
        G.SETTINGS.current_setup = 'Continue'
        G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
        return true
    elseif action == "start" then
        -- the VR "New Run" table: a deck put on the mat, a stake chip on it, START pressed. Like the
        -- run setup's PLAY: the chosen deck becomes the viewed one, deck and stake are remembered,
        -- an unfinished saved run ends the win streak.
        local center = G.P_CENTERS[m.deck or ""]
        local profile = G.PROFILES[G.SETTINGS.profile]
        if not (center and center.set == "Back" and profile) then return false end
        if not (center.unlocked or profile.all_unlocked) then return false end
        local stake = math.floor(tonumber(m.stake) or 1)
        local max_stake = profile.all_unlocked and #G.P_CENTER_POOLS.Stake
            or math.min((get_deck_win_stake(center.key) or 0) + 1, #G.P_CENTER_POOLS.Stake)
        if stake < 1 or stake > max_stake then return false end
        G.GAME.viewed_back = Back(center)
        profile.MEMORY = profile.MEMORY or {}
        profile.MEMORY.deck = center.name
        profile.MEMORY.stake = stake
        G.viewed_stake = stake
        G.SETTINGS.current_setup = 'New Run'
        G.run_setup_seed = nil
        G.challenge_tab = nil
        if not G.SAVED_GAME then
            local raw = get_compressed(G.SETTINGS.profile .. '/' .. 'save.jkr')
            G.SAVED_GAME = raw and STR_UNPACK(raw) or nil
        end
        if G.SAVED_GAME ~= nil then
            local streak = profile.high_scores and profile.high_scores.current_streak
            if streak and not (G.SAVED_GAME.GAME and G.SAVED_GAME.GAME.won) then streak.amt = 0 end
            G:save_settings()
        end
        G.FUNCS.start_run(nil, { stake = stake, seed = nil, challenge = nil })
        return true
    elseif action == "collection" then
        G.FUNCS.your_collection()
        return true
    elseif action == "options" then
        G.FUNCS.options()
        return true
    elseif action == "profile" then -- the name plate: the game's profile select (save slots 1-3)
        G.FUNCS.profile_select({})
        return true
    end
    return false
end }

local function text_row(text, colour, scale)
    return { n = G.UIT.R, config = { align = "cm" }, nodes = {
        { n = G.UIT.T, config = { text = text, scale = scale, colour = colour, shadow = true } },
    } }
end

-- pixel arrow pointing down: a shaft, then ever narrower rows for the head
local function arrow_down(colour)
    local rows = {}
    local function bar(w, h)
        rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = {
            { n = G.UIT.C, config = { minw = w, minh = h, colour = colour } },
        } }
    end
    bar(0.1, 0.22)
    for _, w in ipairs({ 0.4, 0.3, 0.2, 0.1 }) do bar(w, 0.05) end
    return { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = {
        { n = G.UIT.C, config = { align = "cm" }, nodes = rows },
    } }
end

-- "Please Subscribe to UnderTheVRadar", an arrow, and the red YouTube button below
local function youtube_button()
    return { n = G.UIT.C, config = { align = "cm" }, nodes = {
        text_row("Please Subscribe to", G.C.WHITE, 0.35),
        text_row("UnderTheVRadar", G.C.GOLD, 0.4),
        arrow_down(G.C.WHITE),
        { n = G.UIT.R, config = { align = "cm" }, nodes = {
            { n = G.UIT.C, config = { align = "cm", padding = 0.12, r = 0.1, hover = true, shadow = true,
                                      colour = HEX("FF0000"), button = "vr_go_to_youtube" }, nodes = {
                { n = G.UIT.T, config = { text = "YouTube", scale = 0.45, colour = G.C.WHITE, shadow = true } },
            } },
        } },
    } }
end

-- the node whose child carries `button = "go_to_discord"` (or whose child IS `node_wanted`)
local function find_parent_of_button(node, button, node_wanted)
    for _, child in ipairs(node.nodes or {}) do
        if node_wanted and child == node_wanted then return node end
        if button and child.config and child.config.button == button then return node end
        local found = find_parent_of_button(child, button, node_wanted)
        if found then return found end
    end
end

-- "QUIT VR" next to the game's QUIT: closes the VR client, Balatro keeps running.
-- Only shown while a VR client is connected.
G.FUNCS.vr_quit = function(e)
    VR.send_event("quit_vr", {})
end

G.FUNCS.vr_quit_visible = function(e)
    local on = NET.state == "connected"
    if e.states.visible ~= on then e.states.visible = on end
end

-- Discord and X: shown in the flat menu, hidden while a VR client is connected (YouTube takes their place)
G.FUNCS.vr_socials_visible = function(e)
    local on = NET.state ~= "connected"
    if e.states.visible ~= on then e.states.visible = on end
end

-- the YouTube block in the main menu: only while a VR client is connected (flat = the game's own menu)
G.FUNCS.vr_youtube_visible = function(e)
    local on = NET.state == "connected"
    if e.states.visible ~= on then e.states.visible = on end
end

local main_menu_buttons_ref = create_UIBox_main_menu_buttons
function create_UIBox_main_menu_buttons(...)
    local t = main_menu_buttons_ref(...)
    pcall(function()
        -- UIBox_button wraps the real button in a holder: the row is the holder's parent
        local holder = find_parent_of_button(t, "quit")
        local row = holder and find_parent_of_button(t, nil, holder)
        if not row then return end
        local quit_vr = UIBox_button({ button = "vr_quit", colour = G.C.PURPLE or G.C.RED, minw = 2.65, minh = 1.35,
                                       label = { "QUIT ONLY VR" }, scale = 0.45 * 1.2, col = true })
        quit_vr.config.func = "vr_quit_visible"
        -- the gap and the button only exist while VR is connected: the flat menu keeps the game's layout
        row.nodes[#row.nodes + 1] = { n = G.UIT.C, config = { align = "cm", minw = 0.2, func = "vr_quit_visible" }, nodes = {} }
        row.nodes[#row.nodes + 1] = quit_vr
    end)
    local ok, err = pcall(function()
        -- the Discord / X row stays as the game has it; in VR the YouTube block goes ABOVE it. The
        -- block only shows while a VR client is connected, so the flat menu looks like the original.
        local row = find_parent_of_button(t, "go_to_discord")
        local column = row and find_parent_of_button(t, nil, row)
        -- Discord and X share this row: in VR the whole row is hidden, the flat menu keeps it
        if row then
            row.config = row.config or {}
            row.config.func = "vr_socials_visible"
        end
        local block = { n = G.UIT.R, config = { align = "cm", padding = 0.2, func = "vr_youtube_visible" }, nodes = { youtube_button() } }
        if column and column.nodes then
            for i, child in ipairs(column.nodes) do
                if child == row then
                    table.insert(column.nodes, i, block)
                    break
                end
            end
        else -- no Discord row (e.g. non-Steam build): add ours above the language button
            local corner = t.nodes and t.nodes[2]
            if corner and corner.nodes then table.insert(corner.nodes, 1, block) end
        end
    end)
    if not ok then log("youtube button: " .. tostring(err)) end
    return t
end

----------------------------------------------------------------------------
-- VR table interactions: tearing booster packs, reroll lever, coin slot, using consumables
----------------------------------------------------------------------------
-- Booster packs (bought or from a tag) wait until the player tears them open in VR. The game is
-- already in its "using a card" state with the shop moved away, so it simply waits; after
-- PACK_TIMEOUT seconds, or without a VR client, the pack opens by itself.
local PACK_TIMEOUT = 15
local card_open_ref = Card.open
function Card:open()
    if self.ability and self.ability.set == "Booster" and NET.state == "connected" and not self.vr_torn then
        VR.pending_pack = { card = self, since = love.timer.getTime() }
        local c = self.children and self.children.center
        local atlas = c and c.atlas and c.atlas.name
        if atlas then VR.state_atlases[atlas] = true end
        VR.send_event("pack_ready", { uid = oid(self), name = self.ability.name or "",
            atlas = atlas, pos = c and c.sprite_pos and arr({ num(c.sprite_pos.x), num(c.sprite_pos.y) }) or nil })
        return
    end
    return card_open_ref(self)
end

local function release_pack()
    local p = VR.pending_pack
    if not p then return false end
    VR.pending_pack = nil
    p.card.vr_torn = true
    card_open_ref(p.card)
    return true
end

function VR.check_pending_pack()
    local p = VR.pending_pack
    if p and (NET.state ~= "connected" or love.timer.getTime() - p.since > PACK_TIMEOUT or p.card.REMOVED) then
        release_pack()
    end
end

-- The Card Stats chart in VR has its own buttons: another tab (by its label), back to the stats, close.
HANDLERS.card_stats = { gated = false, fn = function(m)
    if not (G.OVERLAY_MENU and VR.usage_open) then return false end
    if m.action == "tab" and type(m.label) == "string" then
        return click_ui_button("tab_but_" .. m.label, G.OVERLAY_MENU)
    elseif m.action == "back" then
        G.FUNCS.high_scores()
        return true
    elseif m.action == "close" then
        G.FUNCS.exit_overlay_menu()
        return true
    end
    return false
end }

----------------------------------------------------------------------------
-- VR collection: the main menu's COLLECTIONS AND STATS opens a shelf in VR instead of the game's
-- collection panels. Every item of each collection page (jokers, decks, vouchers, tarots, planets,
-- spectrals, enhancements, editions, seals, boosters, tags, blinds) with the picture the game shows
-- for it (locked / undiscovered ones get the game's own locked and "?" pictures); its description
-- is read on demand, when VR points at it.
----------------------------------------------------------------------------
local COLL_ATLAS = { Joker = "Joker", Tarot = "Tarot", Planet = "Tarot", Spectral = "Tarot", Voucher = "Voucher",
                     Booster = "Booster" }

local function coll_name(set, key)
    local ok, name = pcall(localize, { type = "name_text", set = set, key = key })
    return (ok and type(name) == "string" and name ~= "ERROR") and name or key
end

local function coll_center(c, cat)
    local disc = c.discovered and true or false
    local unl = c.unlocked ~= false
    local atlas = c.atlas or COLL_ATLAS[c.set] or "centers"
    local pos = c.pos
    if c.set == "Joker" and not unl then atlas, pos = "Joker", G.j_locked.pos
    elseif c.set == "Voucher" and not unl then atlas, pos = "Voucher", G.v_locked.pos
    elseif c.consumeable and not unl then atlas, pos = "Tarot", G.c_locked.pos
    elseif not disc and cat ~= "Back" and cat ~= "Enhanced" then
        local undisc = { Joker = G.j_undiscovered, Edition = G.j_undiscovered, Tarot = G.t_undiscovered,
            Planet = G.p_undiscovered, Spectral = G.s_undiscovered, Voucher = G.v_undiscovered,
            Booster = G.booster_undiscovered }
        if undisc[c.set] then
            pos = undisc[c.set].pos
            atlas = (c.set == "Edition") and "Joker" or (COLL_ATLAS[c.set] or atlas)
        end
    end
    if cat == "Back" or cat == "Enhanced" then disc = unl end -- (decks and enhancements: unlocked = known)
    VR.state_atlases[atlas] = true
    local item = { key = c.key, set = c.set or "", disc = disc, unl = unl, ca = atlas,
                   cp = arr({ num(pos and pos.x), num(pos and pos.y) }) }
    item.name = (disc and unl) and coll_name(c.set, c.key) or (unl and "?????" or "Locked")
    if disc and unl and c.soul_pos then -- legendaries: the floating face over the card
        item.ov = arr({ { a = atlas, p = arr({ num(c.soul_pos.x), num(c.soul_pos.y) }) } })
    end
    if cat == "Edition" and disc then item.ed = c.key end
    return item
end

local function collection_data()
    local cats = arr()
    local function add_cat(id, title, items)
        local found = 0
        for _, it in ipairs(items) do if it.disc and it.unl then found = found + 1 end end
        cats[#cats + 1] = { id = id, title = title, items = items, found = found }
    end
    for _, c in ipairs({ { "Joker", "Jokers" }, { "Back", "Decks" }, { "Voucher", "Vouchers" }, { "Tarot", "Tarots" },
                         { "Planet", "Planets" }, { "Spectral", "Spectrals" }, { "Enhanced", "Enhancements" } }) do
        local items = arr()
        for _, center in ipairs(G.P_CENTER_POOLS[c[1]] or {}) do items[#items + 1] = coll_center(center, c[1]) end
        add_cat(c[1], c[2], items)
    end
    local eds = arr()
    for _, e in ipairs({ "e_base", "e_foil", "e_holo", "e_polychrome", "e_negative" }) do
        if G.P_CENTERS[e] then eds[#eds + 1] = coll_center(G.P_CENTERS[e], "Edition") end
    end
    add_cat("Edition", "Editions", eds)
    local seals = arr()
    local base = G.P_CENTERS.c_base
    VR.state_atlases.centers = true
    for _, s in ipairs(G.P_CENTER_POOLS.Seal or {}) do
        local disc = true -- (the game's own seal page always shows all four)
        local it = { key = s.key, set = "Seal", disc = disc, unl = true, ca = "centers",
                     cp = arr({ num(base.pos.x), num(base.pos.y) }) }
        it.name = disc and coll_name("Other", string.lower(s.key) .. "_seal") or "?????"
        local sp = G.shared_seals and G.shared_seals[s.key] -- (seals have no pos of their own: the shared sprite)
        local spos = sp and sp.sprite_pos
        if disc and spos then it.ov = arr({ { a = "centers", p = arr({ num(spos.x), num(spos.y) }) } }) end
        seals[#seals + 1] = it
    end
    add_cat("Seal", "Seals", seals)
    local packs = arr()
    for _, center in ipairs(G.P_CENTER_POOLS.Booster or {}) do packs[#packs + 1] = coll_center(center, "Booster") end
    add_cat("Booster", "Boosters", packs)
    local tags = {}
    for _, v in pairs(G.P_TAGS or {}) do tags[#tags + 1] = v end
    table.sort(tags, function(a, b) return (a.order or 0) < (b.order or 0) end)
    local tag_items = arr()
    VR.state_atlases.tags = true
    for _, v in ipairs(tags) do
        local disc = v.discovered and true or false
        local pos = disc and v.pos or G.tag_undiscovered.pos
        tag_items[#tag_items + 1] = { key = v.key, set = "Tag", disc = disc, unl = true, ca = "tags", round = true,
            cp = arr({ num(pos.x), num(pos.y) }), name = disc and coll_name("Tag", v.key) or "?????" }
    end
    add_cat("Tag", "Tags", tag_items)
    local blinds = {}
    for _, v in pairs(G.P_BLINDS or {}) do blinds[#blinds + 1] = v end
    table.sort(blinds, function(a, b) return (a.order or 0) < (b.order or 0) end)
    local blind_items = arr()
    VR.state_atlases.blind_chips = true
    for _, v in ipairs(blinds) do
        local disc = v.discovered and true or false
        local pos = disc and v.pos or G.b_undiscovered.pos
        blind_items[#blind_items + 1] = { key = v.key, set = "Blind", disc = disc, unl = true, ca = "blind_chips", round = true,
            cp = arr({ 0, num(pos.y) }), name = disc and coll_name("Blind", v.key) or "?????" }
    end
    add_cat("Blind", "Blinds", blind_items)
    return { cats = cats }
end

-- The description of one collection item, as the game would show it when hovering it there.
local function collection_text(key, set)
    if set == "Seal" then
        local s = G.P_SEALS and G.P_SEALS[key]
        local nodes = {}
        localize({ type = "descriptions", set = "Other", key = string.lower(key) .. "_seal", nodes = nodes })
        return loc_lines(nodes)
    elseif set == "Tag" then
        local v = G.P_TAGS[key]
        local tag = Tag(key, true)
        if not (v and v.discovered) then tag.hide_ability = true end
        local holder = {}
        tag:get_uibox_table(holder)
        return loc_lines(holder.ability_UIBox_table and holder.ability_UIBox_table.main or {})
    elseif set == "Blind" then
        local v = G.P_BLINDS[key]
        if not (v and v.discovered) then return "Defeat this blind to discover it" end
        local vars = v.vars or {}
        if v.name == "The Ox" then vars = { localize("ph_most_played") } end
        local lines = localize({ type = "raw_descriptions", key = key, set = "Blind", vars = vars }) or {}
        local out = {}
        for _, l in ipairs(type(lines) == "table" and lines or {}) do out[#out + 1] = tostring(l) end
        if v.mult then out[#out + 1] = "Score: " .. tostring(v.mult) .. "x base" end
        if v.dollars then out[#out + 1] = "Reward: " .. string.rep("$", v.dollars) end
        return table.concat(out, "\n")
    end
    local c = G.P_CENTERS[key]
    if not c then return "" end
    if set == "Back" then
        local ok, text = pcall(function() return definition_text(Back(c):generate_UI()) end)
        return ok and text or ""
    end
    local front = (set == "Enhanced" or set == "Edition") and G.P_CARDS.empty or nil
    local card = Card(0, 0, G.CARD_W, G.CARD_H, front, c)
    if set == "Edition" and c.discovered then
        pcall(function() card:set_edition({ [string.sub(key, 3)] = true }, true, true) end)
    end
    local ok, ui = pcall(function() return card:generate_UIBox_ability_table() end)
    local text = (ok and ui and ui.main) and loc_lines(ui.main) or ""
    card:remove()
    return text
end

HANDLERS.collection = { gated = false, fn = function(m)
    if m.action == "open" then
        local ok, data = pcall(collection_data)
        if not ok then log("collection: " .. tostring(data)) return false end
        send("collection", encode(data))
        return true
    elseif m.action == "info" and type(m.key) == "string" then
        local ok, text = pcall(collection_text, m.key, tostring(m.set or ""))
        if not ok then log("collection info: " .. tostring(text)) text = "" end
        send("collection_info", encode({ key = m.key, text = text }))
        return true
    elseif m.action == "stats" then -- Stats -> Card Stats: the columns around you
        if G.STAGE ~= G.STAGES.MAIN_MENU then return false end
        G.FUNCS.usage()
        return true
    end
    return false
end }

-- A key of VR's keyboard: typed into the text box on screen (hooked first, as a click on it would).
HANDLERS.text_key = { gated = false, fn = function(m)
    local e = VR.text_box
    if not (e and VR.text_box_t and love.timer.getTime() - VR.text_box_t < 0.5) or type(m.key) ~= "string" then return false end
    if G.CONTROLLER.text_input_hook ~= e then
        -- hooked the way a click on the box does it (Steamodded also needs the box's id then)
        local box = e.parent and e.parent.parent
        if not (box and box.children and box.children[1] and box.children[1].children[1] == e) then return false end
        G.FUNCS.select_text_input(box)
    end
    local args = e.config.ref_table
    if m.key == "0" and args.extended_corpus then
        -- a real 0 in a name (the game would turn it into an "o"; seeds keep that rule)
        local t = args.text
        TRANSPOSE_TEXT_INPUT(0)
        if string.len(t.ref_table[t.ref_value] or "") < (args.max_length or 16) then
            MODIFY_TEXT_INPUT({ letter = "0", text_table = t, pos = t.current_position + 1 })
            TRANSPOSE_TEXT_INPUT(1)
        end
        return true
    end
    G.FUNCS.text_input_key({ key = m.key, caps = m.caps and true or false })
    return true
end }

-- The VR menu's "Run Info" and "Game Options" (the run panel with these buttons isn't shown in VR)
HANDLERS.game_menu = { gated = true, fn = function(m)
    if m.action == "run_info" then
        if G.STAGE ~= G.STAGES.RUN then return false end
        G.FUNCS.run_info()
        return true
    elseif m.action == "options" then
        G.FUNCS.options()
        return true
    end
    return false
end }

HANDLERS.open_pack = { gated = false, fn = function() return release_pack() end }

-- The Wheel of Fortune card in VR: a little wheel of fortune is spun first ("VR: Wheel of Fortune"):
--   Real:          the wheel decides. The card's effect waits until the wheel has stopped; then the
--                  game's own roll (pseudorandom 'wheel_of_fortune') is answered with the wheel's
--                  result. The wheel has as many WIN! fields as the chance (2 of 8 = 1 in 4).
--   Deterministic: the game's roll decides as always (a seeded run stays the same): it is looked at
--                  beforehand without using it up (the random state is put back), so the wheel can
--                  stop on the right kind of field; the effect waits behind a blocking event.
--   Off:           the card works at once, like in the game.
-- Without a VR client, or WHEEL_TIMEOUT seconds without an answer, the game's own roll decides.
local WHEEL_TIMEOUT = 60
VR.force_wheel = nil -- true / false: the next 'wheel_of_fortune' roll wins / loses (Real)
local pseudorandom_ref = pseudorandom
function pseudorandom(seed, min, max)
    if seed == "wheel_of_fortune" and VR.force_wheel ~= nil and not min then
        local win = VR.force_wheel
        VR.force_wheel = nil
        pseudorandom_ref(seed) -- (the seed stream moves on as if rolled)
        return win and 0 or 1
    end
    return pseudorandom_ref(seed, min, max)
end

local card_use_consumeable_ref = Card.use_consumeable
function Card:use_consumeable(area, copier)
    local mode = VR.wheel_mode
    local chance = self.ability and self.ability.name == "The Wheel of Fortune" and
        G.GAME.probabilities.normal / self.ability.extra
    if not chance or chance >= 1 or mode == "Off" or NET.state ~= "connected" then
        return card_use_consumeable_ref(self, area, copier)
    end
    local real = mode ~= "Deterministic"
    local win = false
    if not real then
        local key = "wheel_of_fortune"
        local saved = G.GAME.pseudorandom[key]
        win = pseudorandom_ref(key) < chance
        G.GAME.pseudorandom[key] = saved -- (the real roll in the original below gives the same number)
    end
    local w = { done = false }
    VR.wheel = w
    G.E_MANAGER:add_event(Event({ func = function()
        w.since = love.timer.getTime()
        VR.send_event("wheel", { win = win, chance = chance, real = real })
        return true
    end }))
    G.E_MANAGER:add_event(Event({ func = function()
        return w.done or NET.state ~= "connected" or love.timer.getTime() - (w.since or 0) > WHEEL_TIMEOUT
    end }))
    if not real then
        return card_use_consumeable_ref(self, area, copier)
    end
    -- Real: the card's effect only once the wheel has stopped, with the wheel's result
    G.E_MANAGER:add_event(Event({ func = function()
        if w.win ~= nil then VR.force_wheel = w.win end
        card_use_consumeable_ref(self, area, copier)
        VR.force_wheel = nil
        return true
    end }))
end

HANDLERS.wheel_done = { gated = false, fn = function(m)
    if not VR.wheel then return false end
    if m.win ~= nil then VR.wheel.win = (m.win == true or m.win == "true") end
    VR.wheel.done = true
    VR.wheel = nil
    return true
end }

-- Reroll lever on the VR joker board
HANDLERS.reroll = { gated = true, fn = function()
    if not can_reroll_now() then return false end
    G.FUNCS.reroll_shop()
    return true
end }

-- Coin slot on the VR joker board: sell a joker or consumable
HANDLERS.sell = { gated = true, fn = function(m)
    local card = objs[m.target or -1]
    if not is_a(card, Card) or not card:can_sell_card() then return false end
    G.FUNCS.sell_card({ config = { ref_table = card } })
    return true
end }

-- Buying from the VR shop counter (an item taken off the counter): jokers, consumables and playing
-- cards are bought like with the Buy button, vouchers are redeemed and booster packs opened like
-- with their own buttons. Refused (ok = false) if it can't be afforded or there is no room.
HANDLERS.buy = { gated = true, fn = function(m)
    local card = objs[m.target or -1]
    if not is_a(card, Card) or not card.area then return false end
    local area = card.area
    if area ~= G.shop_jokers and area ~= G.shop_vouchers and area ~= G.shop_booster then return false end
    local cost = card.cost or 0
    if cost > 0 and cost > (G.GAME.dollars or 0) - (G.GAME.bankrupt_at or 0) then return false end
    -- "buy and use" (m.use): a tarot / planet / spectral card dropped on the card hand or thrown up
    -- straight from the counter. Only when the game's own BUY AND USE button would be there.
    if m.use then
        if area ~= G.shop_jokers or not (card.ability and card.ability.consumeable) then return false end
        local ok, usable = pcall(function() return card:can_use_consumeable() end)
        if not (ok and usable) then return false end
        G.FUNCS.buy_from_shop({ config = { ref_table = card, id = 'buy_and_use' } })
        return true
    end
    if area == G.shop_jokers then
        return G.FUNCS.buy_from_shop({ config = { ref_table = card } }) ~= false
    end
    G.FUNCS.use_card({ config = { ref_table = card } }) -- redeem the voucher / open the pack
    return true
end }

-- "Next Round" on the VR shop counter: clicks the shop's own Next Round button
HANDLERS.next_round = { gated = true, fn = function()
    return G.STATE == G.STATES.SHOP and click_ui_button("next_round_button", G.shop) -- (in the shop's own UIBox)
end }

-- A tarot / planet / spectral card used with a VR gesture (dropped on the hand, thrown into the sky)
HANDLERS.use = { gated = true, fn = function(m)
    local card = objs[m.target or -1]
    if not is_a(card, Card) or not card.ability or not card.ability.consumeable then return false end
    if not card:can_use_consumeable() then return false end
    G.FUNCS.use_card({ config = { ref_table = card } })
    return true
end }

-- Scoring popups ("+30", "+4 Mult", "X2", "$3" ...): sent when the game shows them, so VR can let
-- the card on the table pop at the same moment
local SCORE_TEXT = {
    chips = function(a) return "+" .. tostring(a), G.C.CHIPS end,
    mult = function(a) return "+" .. tostring(a) .. " Mult", G.C.MULT end,
    x_mult = function(a) return "X" .. tostring(a), G.C.MULT end,
    dollars = function(a) return "$" .. tostring(a), G.C.MONEY end,
    debuff = function() return localize("k_debuffed"), G.C.RED end, -- a boss blind disabled the card
}
local eval_text_ref = card_eval_status_text
function card_eval_status_text(card, eval_type, amt, percent, dir, extra)
    local result = eval_text_ref(card, eval_type, amt, percent, dir, extra)
    if NET.state ~= "connected" then return result end
    pcall(function()
        local text, colour
        if SCORE_TEXT[eval_type] and (amt or eval_type == "debuff") then text, colour = SCORE_TEXT[eval_type](amt) end
        if type(extra) == "table" and extra.message then text, colour = extra.message, extra.colour or colour end
        if not text then return end
        local uid = card and oid(card) or nil
        G.E_MANAGER:add_event(Event({ func = function() -- right after the game's own popup
            pcall(VR.send_event, "score", { uid = uid, text = tostring(text), kind = eval_type or "", c = col(colour or G.C.WHITE) })
            return true
        end }))
    end)
    return result
end

-- Glass cards breaking
local shatter_ref = Card.shatter
function Card:shatter()
    if NET.state == "connected" then
        pcall(function()
            local ch = self.children or {}
            local function pos(s) return s and s.sprite_pos and arr({ num(s.sprite_pos.x), num(s.sprite_pos.y) }) or nil end
            VR.send_event("shatter", { uid = oid(self),
                ca = ch.center and ch.center.atlas and ch.center.atlas.name, cp = pos(ch.center),
                fa = ch.front and ch.front.atlas and ch.front.atlas.name, fp = pos(ch.front) })
        end)
    end
    return shatter_ref(self)
end

-- Spatial sound: while VR is connected the game's sound effects play in VR, where they happen
-- (cards at the hand, coins at the coin pile ...). Each sound file is sent once; music stays here.
VR.sent_sounds = {}

local function send_sound_file(sound_code)
    if VR.sent_sounds[sound_code] then return true end
    local data = love.filesystem.read("resources/sounds/" .. sound_code .. ".ogg")
    if not data then return false end
    send("sound_data", encode({ code = sound_code, data = love.data.encode("string", "base64", data) }))
    VR.sent_sounds[sound_code] = true
    return true
end

-- The casino in VR plays some of the game's sounds by itself (coins of a slot machine payout,
-- chips at the side tables): sent right after connecting, one per frame, before they are needed.
local AMBIENT_SOUNDS = { "coin1", "coin2", "coin3", "coin4", "coin5", "coin6", "coin7", "chips1", "chips2",
                         -- (Solatro, which runs in VR alone: its cards' sounds)
                         "cardSlide1", "card1", "multhit1", "whoosh1",
                         -- (the casino's card tables: shuffling and dealing; a crumpled slot ticket)
                         "cardFan2", "cardSlide2", "card3", "crumple1", "crumple2", "crumple3" }
function VR.send_ambient_sounds()
    if NET.state ~= "connected" then return end
    for _, code in ipairs(AMBIENT_SOUNDS) do
        if not VR.sent_sounds[code] then send_sound_file(code); return end
    end
end

local play_sound_ref = play_sound
function play_sound(sound_code, per, vol)
    if NET.state == "connected" and type(sound_code) == "string" and not G.F_MUTE then
        local path = "resources/sounds/" .. sound_code .. ".ogg"
        local ok_file = VR.sent_sounds[sound_code] or love.filesystem.getInfo(path) ~= nil
        if ok_file then
            if not VR.sent_sounds[sound_code] then
                local data = love.filesystem.read(path)
                if data then
                    send("sound_data", encode({ code = sound_code, data = love.data.encode("string", "base64", data) }))
                    VR.sent_sounds[sound_code] = true
                end
            end
            if VR.sent_sounds[sound_code] then
                local s = G.SETTINGS and G.SETTINGS.SOUND or {}
                local volume = (num(s.volume) / 100) * (num(s.game_sounds_volume or 100) / 100) * (vol or 1)
                VR.send_event("sound", { code = sound_code, per = r3(per or 1), vol = r3(volume) })
                return
            end
        end
    end
    return play_sound_ref(sound_code, per, vol)
end

-- Shop purchases => particle effects in VR
local buy_from_shop_ref = G.FUNCS.buy_from_shop
G.FUNCS.buy_from_shop = function(e)
    local card = e and e.config and e.config.ref_table
    local info = card and card.ability and {
        set = card.ability.set or "", key = card.config.center.key, name = card.ability.name or "",
        uid = oid(card), -- VR lets the bought card fly from the shop to its place
    }
    local result = buy_from_shop_ref(e)
    if info and result ~= false then VR.send_event("shop_buy", info) end
    return result
end

-- Cards taken/used from booster packs or the consumable slots (Planet, Tarot, Spectral)
local use_card_ref = G.FUNCS.use_card
G.FUNCS.use_card = function(e, mute, nosave)
    local card = e and e.config and e.config.ref_table
    local info = card and card.ability and {
        set = card.ability.set or "", key = card.config.center.key, name = card.ability.name or "",
        from_pack = (card.area == G.pack_cards),
    }
    use_card_ref(e, mute, nosave)
    if info then VR.send_event("card_used", info) end
end

----------------------------------------------
------------MOD CODE END----------------------
