local mod = SMODS and SMODS.current_mod
local ffi = require("ffi")

local function log(msg)
    if sendInfoMessage then sendInfoMessage(msg, "SpotifyBalatro") else print("[SpotifyBalatro] " .. msg) end
end

local dirname = ((mod and mod.path) or ""):match("([^/\\]+)[/\\]*$") or "SpotifyBalatro"
local REL = "Mods/" .. dirname .. "/"
local ABS = (love.filesystem.getSaveDirectory() .. "/Mods/" .. dirname):gsub("\\", "/")

local DEFAULTS = {
    show = true, corner = 1, size = 1.0, opacity = 1.0, accent = 1,
    popup = true, popup_time = 5, sounds = true, hotkeys = false,
    show_bar = true, show_time = true, scroll = true, open = false,
}
local cfg = (mod and mod.config) or {}
if mod and not mod.config then mod.config = cfg end
for k, v in pairs(DEFAULTS) do
    if cfg[k] == nil then cfg[k] = v end
end
cfg.corner = math.min(4, math.max(1, math.floor(tonumber(cfg.corner) or 1)))
cfg.accent = math.max(1, math.floor(tonumber(cfg.accent) or 1))
cfg.size = math.min(1.6, math.max(0.6, tonumber(cfg.size) or 1))
cfg.opacity = math.min(1, math.max(0.3, tonumber(cfg.opacity) or 1))
cfg.popup_time = math.min(15, math.max(2, tonumber(cfg.popup_time) or 5))

local function save_cfg()
    if mod and SMODS.save_mod_config then pcall(SMODS.save_mod_config, mod) end
end

local S = {
    status = "none", title = "", artist = "", pos = 0, dur = 0,
    ts = 0, read_at = 0, key = "", track_t0 = 0,
}
local UI = { anim = cfg.open and 1 or 0, toast = 0, poll = 0, errors = 0 }
local hit = {}
local swallow = nil
local started_at = love.timer.getTime()

local function launch_helper()
    love.filesystem.remove(REL .. "state.txt")
    love.filesystem.remove(REL .. "cmd.txt")
    pcall(ffi.cdef, "unsigned long GetCurrentProcessId(void);")
    pcall(ffi.cdef, "void* ShellExecuteA(void* hwnd, const char* op, const char* file, const char* params, const char* dir, int show);")
    local ok, err = pcall(function()
        local shell = ffi.load("shell32")
        local pid = ffi.C.GetCurrentProcessId()
        local params = string.format(
            '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s/helper.ps1" -GamePid %d -Dir "%s"',
            ABS, tonumber(pid), ABS)
        shell.ShellExecuteA(nil, "open", "powershell.exe", params, nil, 0)
    end)
    if not ok then log("Helper konnte nicht gestartet werden: " .. tostring(err)) end
end

local function read_state()
    local data = love.filesystem.read(REL .. "state.txt")
    if not data then return end
    local t = {}
    for k, v in data:gmatch("(%w+)=([^\n]*)") do t[k] = v end
    S.status = t.status or "none"
    S.title = t.title or ""
    S.artist = t.artist or ""
    S.pos = tonumber(t.pos) or 0
    S.dur = tonumber(t.dur) or 0
    S.ts = tonumber(t.ts) or 0
    S.read_at = love.timer.getTime()
    local key = S.title .. "|" .. S.artist
    if key ~= S.key then
        S.key = key
        S.track_t0 = love.timer.getTime()
        if cfg.popup and S.status == "playing" and S.title ~= "" then UI.toast = cfg.popup_time end
    end
end

local function send(cmd)
    if S.status == "none" then return end
    love.filesystem.write(REL .. "cmd.txt", cmd)
    if cmd == "toggle" then S.status = (S.status == "playing") and "paused" or "playing" end
    if cmd == "next" or cmd == "prev" then S.pos = 0; S.read_at = love.timer.getTime() end
end

local function helper_alive()
    return S.ts > 0 and math.abs(os.time() - S.ts) <= 5
end

local function click_sound()
    if cfg.sounds and play_sound then pcall(play_sound, "button", 1, 0.5) end
end

local C = {
    shadow = { 0, 0, 0, 0.35 },
    frame  = { 0.30, 0.36, 0.38, 1 },
    panel  = { 0.157, 0.188, 0.20, 1 },
    inset  = { 0.10, 0.125, 0.135, 1 },
    white  = { 1, 1, 1, 1 },
    dim    = { 0.62, 0.70, 0.72, 1 },
    green  = { 0.294, 0.761, 0.573, 1 },
    blue   = { 0.0, 0.616, 1.0, 1 },
    orange = { 0.992, 0.635, 0.0, 1 },
    red    = { 0.996, 0.373, 0.333, 1 },
    purple = { 0.62, 0.42, 0.86, 1 },
    spot   = { 0.114, 0.725, 0.329, 1 },
}

local ACCENTS = {
    { name = "Balatro Green", c = C.green },
    { name = "Spotify Green", c = C.spot },
    { name = "Blue", c = C.blue },
    { name = "Red", c = C.red },
    { name = "Orange", c = C.orange },
    { name = "Purple", c = C.purple },
}
if cfg.accent > #ACCENTS then cfg.accent = 1 end

local function accent() return ACCENTS[cfg.accent] and ACCENTS[cfg.accent].c or C.green end

local fonts = {}
local function font(size)
    size = math.max(8, math.floor(size + 0.5))
    if not fonts[size] then
        local ok, f = pcall(love.graphics.newFont, "resources/fonts/m6x11plus.ttf", size)
        if not ok then f = love.graphics.newFont(size) end
        pcall(f.setFilter, f, "nearest", "nearest")
        fonts[size] = f
    end
    return fonts[size]
end

local galpha = 1
local function setc(c, a)
    love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1) * galpha)
end

local function darker(c, f)
    return { c[1] * f, c[2] * f, c[3] * f, c[4] or 1 }
end

local function safe_text(text, fnt)
    if text == "" then return "" end
    local out, last_q = {}, false
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local ok, has = pcall(fnt.hasGlyphs, fnt, ch)
        if ok and has then
            out[#out + 1] = ch; last_q = false
        elseif not last_q then
            out[#out + 1] = "?"; last_q = true
        end
    end
    return table.concat(out)
end

local function truncate(text, fnt, wmax)
    if fnt:getWidth(text) <= wmax then return text end
    while #text > 1 and fnt:getWidth(text .. "...") > wmax do
        text = text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
    end
    return text .. "..."
end

local function fmt_time(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function inside(r, x, y)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function draw_logo(cx, cy, r)
    setc(C.spot)
    love.graphics.circle("fill", cx, cy, r)
    setc(C.white)
    love.graphics.setLineWidth(math.max(1.5, r * 0.16))
    love.graphics.setLineJoin("bevel")
    local arcs = { { 0.62, -0.30, 0.17 }, { 0.52, 0.00, 0.14 }, { 0.42, 0.28, 0.11 } }
    for _, a in ipairs(arcs) do
        local pts = {}
        for i = -6, 6 do
            local t = i / 6
            pts[#pts + 1] = cx + t * a[1] * r
            pts[#pts + 1] = cy + a[2] * r - (1 - t * t) * a[3] * r
        end
        love.graphics.line(pts)
    end
end

local function button(id, x, y, w, h, color, s, enabled, icon)
    local mx, my = love.mouse.getPosition()
    local r = { x = x, y = y, w = w, h = h, id = id }
    hit[#hit + 1] = r
    local hover = enabled and inside(r, mx, my)
    local down = hover and love.mouse.isDown(1)
    local lift = down and 0 or (hover and 3 * s or 2 * s)
    local press = down and 2 * s or 0
    local edge = 4 * s
    local base = enabled and color or { 0.35, 0.40, 0.42, 1 }
    setc(darker(base, 0.55))
    love.graphics.rectangle("fill", x, y + edge - press, w, h, 6 * s, 6 * s)
    setc(base)
    love.graphics.rectangle("fill", x, y + edge - lift - press, w, h, 6 * s, 6 * s)
    setc(C.white)
    icon(x + w / 2, y + edge - lift - press + h / 2, h * 0.28)
end

local icons = {
    prev = function(cx, cy, r)
        love.graphics.rectangle("fill", cx - r * 1.05, cy - r, r * 0.4, r * 2)
        love.graphics.polygon("fill", cx + r * 1.0, cy - r, cx + r * 1.0, cy + r, cx - r * 0.6, cy)
    end,
    next = function(cx, cy, r)
        love.graphics.rectangle("fill", cx + r * 0.65, cy - r, r * 0.4, r * 2)
        love.graphics.polygon("fill", cx - r * 1.0, cy - r, cx - r * 1.0, cy + r, cx + r * 0.6, cy)
    end,
    play = function(cx, cy, r)
        love.graphics.polygon("fill", cx - r * 0.75, cy - r * 1.1, cx - r * 0.75, cy + r * 1.1, cx + r * 1.0, cy)
    end,
    pause = function(cx, cy, r)
        love.graphics.rectangle("fill", cx - r * 0.85, cy - r, r * 0.6, r * 2)
        love.graphics.rectangle("fill", cx + r * 0.25, cy - r, r * 0.6, r * 2)
    end,
}

local function marquee(text, fnt, x, y, wmax, color, s, now)
    love.graphics.setFont(fnt)
    setc(color)
    local tw = fnt:getWidth(text)
    if tw <= wmax then
        love.graphics.print(text, math.floor(x), math.floor(y))
        return
    end
    if not cfg.scroll then
        love.graphics.print(truncate(text, fnt, wmax), math.floor(x), math.floor(y))
        return
    end
    local gap = 36 * s
    local cycle = tw + gap
    local speed = 38 * s
    local pause = 1.6
    local t = (now - S.track_t0) % (cycle / speed + pause)
    local off = math.max(0, t - pause) * speed
    local sx, sy, sw, sh = love.graphics.getScissor()
    love.graphics.setScissor(math.floor(x), math.floor(y - 2), math.floor(wmax), fnt:getHeight() + 6)
    love.graphics.print(text, math.floor(x - off), math.floor(y))
    love.graphics.print(text, math.floor(x - off + cycle), math.floor(y))
    love.graphics.setScissor(sx, sy, sw, sh)
end

local NEXT_CORNER = { [1] = 2, [2] = 4, [4] = 3, [3] = 1 }

local function draw_overlay()
    if not (G and G.SETTINGS and G.STAGE) then return end
    local dt = love.timer.getDelta()
    local now = love.timer.getTime()
    local w, h = love.graphics.getDimensions()
    local s = math.min(2.4, math.max(0.5, h / 1080 * cfg.size))

    UI.poll = UI.poll - dt
    if UI.poll <= 0 then UI.poll = 0.25; read_state() end
    if UI.toast > 0 then UI.toast = UI.toast - dt end

    hit = {}
    if not cfg.show then return end

    local target = (cfg.open or UI.toast > 0) and 1 or 0
    UI.anim = UI.anim + (target - UI.anim) * math.min(1, dt * 12)
    if math.abs(target - UI.anim) < 0.01 then UI.anim = target end

    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.setScissor()
    love.graphics.setLineStyle("smooth")

    local acc = accent()
    local sec = (acc == C.blue) and C.orange or C.blue
    local m, bd = 16 * s, 56 * s
    local pw = 360 * s
    local ph = (96 + (cfg.show_bar and 12 or 0) + (cfg.show_time and 20 or 0)) * s
    local left = (cfg.corner == 1 or cfg.corner == 3)
    local bottom = (cfg.corner == 3 or cfg.corner == 4)
    local bx = left and m or (w - m - bd)
    local by = bottom and (h - m - bd) or m

    if UI.anim > 0.02 then
        local slide = (1 - UI.anim) * 24 * s * (left and -1 or 1)
        local px = (left and (bx + bd + 10 * s) or (bx - 10 * s - pw)) + slide
        local py = bottom and (by + bd - ph) or by
        galpha = UI.anim * cfg.opacity
        local pad = 12 * s
        local alive = helper_alive() or (now - started_at < 6)
        local live = alive and S.status ~= "none"

        setc(C.shadow)
        love.graphics.rectangle("fill", px, py + 6 * s, pw, ph, 12 * s, 12 * s)
        setc(C.frame)
        love.graphics.rectangle("fill", px, py, pw, ph, 12 * s, 12 * s)
        setc(C.panel)
        love.graphics.rectangle("fill", px + 4 * s, py + 4 * s, pw - 8 * s, ph - 8 * s, 9 * s, 9 * s)
        if UI.anim > 0.5 then hit[#hit + 1] = { x = px, y = py, w = pw, h = ph, id = "panel" } end

        local fh, ft, fa, fs = font(15 * s), font(24 * s), font(18 * s), font(15 * s)
        local colw = pw - pad * 2 - 124 * s - 10 * s

        draw_logo(px + pad + 7 * s, py + pad + 9 * s, 7 * s)
        love.graphics.setFont(fh)
        local head = (S.status == "playing" and "NOW PLAYING") or (S.status == "paused" and "PAUSED") or "SPOTIFY"
        setc(S.status == "playing" and acc or C.dim)
        love.graphics.print(head, math.floor(px + pad + 20 * s), math.floor(py + pad))

        local title, artist
        if not alive then
            title, artist = "Helper not running", "Restart Balatro"
        elseif S.status == "none" then
            title, artist = "Spotify offline", "Start Spotify and play a song"
        else
            title = S.title ~= "" and S.title or "Unknown"
            artist = S.artist
        end
        title = safe_text(title, ft)
        artist = truncate(safe_text(artist, fa), fa, colw)
        marquee(title, ft, px + pad, py + pad + 22 * s, colw, C.white, s, now)
        love.graphics.setFont(fa)
        setc(C.dim)
        love.graphics.print(artist, math.floor(px + pad), math.floor(py + pad + 52 * s))

        local bw, bh, gap = 36 * s, 34 * s, 8 * s
        local bxx = px + pw - pad - 3 * bw - 2 * gap
        local byy = py + pad + 8 * s
        button("prev", bxx, byy, bw, bh, sec, s, live, icons.prev)
        button("toggle", bxx + bw + gap, byy, bw, bh, acc, s, live,
            S.status == "playing" and icons.pause or icons.play)
        button("next", bxx + 2 * (bw + gap), byy, bw, bh, sec, s, live, icons.next)

        local pos = S.pos
        if S.status == "playing" then pos = pos + (now - S.read_at) end
        if S.dur > 0 and pos > S.dur then pos = S.dur end
        local barx, bary, barw, barh = px + pad, py + 90 * s, pw - pad * 2, 8 * s
        local ty = bary
        if cfg.show_bar then
            setc(C.inset)
            love.graphics.rectangle("fill", barx, bary, barw, barh, barh / 2, barh / 2)
            if live and S.dur > 0 then
                local fill = math.max(barh, barw * (pos / S.dur))
                setc(acc)
                love.graphics.rectangle("fill", barx, bary, fill, barh, barh / 2, barh / 2)
            end
            ty = bary + barh + 3 * s
        end
        if cfg.show_time then
            love.graphics.setFont(fs)
            setc(C.dim)
            love.graphics.print(live and fmt_time(pos) or "-:--", math.floor(barx), math.floor(ty))
            local tot = live and S.dur > 0 and fmt_time(S.dur) or "-:--"
            love.graphics.print(tot, math.floor(barx + barw - fs:getWidth(tot)), math.floor(ty))
        end
    end

    do
        galpha = cfg.opacity
        local cx, cy, r = bx + bd / 2, by + bd / 2, bd / 2
        local mx, my = love.mouse.getPosition()
        hit[#hit + 1] = { x = bx, y = by, w = bd, h = bd, id = "main" }
        local hover = (mx - cx) ^ 2 + (my - cy) ^ 2 <= r * r
        local lift = hover and 3 * s or 0
        setc(C.shadow)
        love.graphics.circle("fill", cx, cy + 5 * s, r)
        setc(C.frame)
        love.graphics.circle("fill", cx, cy + 3 * s - lift * 0.5, r)
        setc(C.panel)
        love.graphics.circle("fill", cx, cy + 3 * s - lift * 0.5, r - 4 * s)
        draw_logo(cx, cy + 3 * s - lift * 0.5, r - 9 * s)
        if S.status == "paused" then
            setc(C.orange)
            love.graphics.circle("fill", cx + r * 0.72, cy - r * 0.72 + 3 * s, 6 * s)
        end
    end

    galpha = 1
    love.graphics.pop()
end

local function handle_press(x, y, button)
    for i = #hit, 1, -1 do
        local r = hit[i]
        if r.id == "main" then
            local cx, cy, rad = r.x + r.w / 2, r.y + r.h / 2, r.w / 2
            if (x - cx) ^ 2 + (y - cy) ^ 2 <= rad * rad then
                if button == 1 then
                    cfg.open = not cfg.open
                    UI.toast = 0
                    save_cfg()
                elseif button == 2 then
                    cfg.corner = NEXT_CORNER[cfg.corner] or 1
                    save_cfg()
                end
                click_sound()
                return true
            end
        elseif inside(r, x, y) then
            if button == 1 and (r.id == "prev" or r.id == "toggle" or r.id == "next") then
                send(r.id)
                click_sound()
            end
            return true
        end
    end
    return false
end

local CORNER_NAMES = { "Top Left", "Top Right", "Bottom Left", "Bottom Right" }
local ACCENT_NAMES = {}
for i, a in ipairs(ACCENTS) do ACCENT_NAMES[i] = a.name end

G.FUNCS.spotbal_corner = function(args) cfg.corner = args.to_key end
G.FUNCS.spotbal_accent = function(args) cfg.accent = args.to_key end

local function build_config_tab()
    do
        local on = HEX and HEX("1DB954") or G.C.GREEN
        local function toggle(label, key)
            return create_toggle({
                label = label, ref_table = cfg, ref_value = key,
                active_colour = on, scale = 0.85, label_scale = 0.38, w = 3.6,
            })
        end
        local function slider(label, key, min, max, decimals)
            return create_slider({
                label = label, ref_table = cfg, ref_value = key, colour = on,
                min = min, max = max, decimal_places = decimals, w = 3.6, h = 0.4,
                label_scale = 0.4, text_scale = 0.32,
            })
        end
        local function cycle(label, options, current, cb)
            return {
                n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = {
                    { n = G.UIT.R, config = { align = "cm" }, nodes = {
                        { n = G.UIT.T, config = { text = label, scale = 0.4, colour = G.C.UI.TEXT_LIGHT } } } },
                    { n = G.UIT.R, config = { align = "cm" }, nodes = {
                        create_option_cycle({
                            options = options, current_option = current, opt_callback = cb,
                            scale = 0.7, w = 4.0, colour = on,
                        }) } },
                },
            }
        end
        local function column(nodes)
            return { n = G.UIT.C, config = { align = "tm", padding = 0.1 }, nodes = nodes }
        end
        local function page(columns)
            return {
                n = G.UIT.ROOT, config = { align = "cm", padding = 0.15, colour = G.C.CLEAR, minh = 4.2 },
                nodes = columns,
            }
        end

        local tabs = {
            {
                label = "Look", chosen = true,
                tab_definition_function = function()
                    return page({
                        column({ cycle("Position", CORNER_NAMES, cfg.corner, "spotbal_corner"),
                                 slider("Size", "size", 0.6, 1.6, 1) }),
                        column({ cycle("Accent color", ACCENT_NAMES, cfg.accent, "spotbal_accent"),
                                 slider("Opacity", "opacity", 0.3, 1.0, 1) }),
                    })
                end,
            },
            {
                label = "Behavior", chosen = false,
                tab_definition_function = function()
                    return page({
                        column({ toggle("Show button", "show"),
                                 toggle("Keep panel open", "open"),
                                 toggle("Popup on new song", "popup"),
                                 slider("Popup seconds", "popup_time", 2, 15, 0) }),
                        column({ toggle("Progress bar", "show_bar"),
                                 toggle("Time", "show_time"),
                                 toggle("Scrolling title", "scroll"),
                                 toggle("Click sounds", "sounds"),
                                 toggle("Hotkeys F6 / F7 / F8", "hotkeys") }),
                    })
                end,
            },
        }
        return {
            n = G.UIT.ROOT, config = { align = "cm", padding = 0.05, colour = G.C.CLEAR },
            nodes = { create_tabs({ tabs = tabs, snap_to_nav = true, colour = on, tab_h = 4.4, tab_w = 9 }) },
        }
    end
end

if mod then
    mod.config_tab = function()
        local ok, res = pcall(build_config_tab)
        if ok then return res end
        log("Config-Menue Fehler: " .. tostring(res))
        return {
            n = G.UIT.ROOT, config = { align = "cm", padding = 0.2, colour = G.C.CLEAR },
            nodes = { { n = G.UIT.T, config = { text = "Config menu error - see Lovely log", scale = 0.5, colour = G.C.UI.TEXT_LIGHT } } },
        }
    end
end

launch_helper()

local orig_draw = love.draw
love.draw = function(...)
    if orig_draw then orig_draw(...) end
    if UI.errors < 5 then
        local ok, err = pcall(draw_overlay)
        if not ok then
            UI.errors = UI.errors + 1
            galpha = 1
            log("Zeichenfehler: " .. tostring(err))
        end
    end
end

local orig_pressed = love.mousepressed
love.mousepressed = function(x, y, button, ...)
    local ok, handled = pcall(handle_press, x, y, button)
    if ok and handled then
        swallow = button
        return
    end
    if orig_pressed then return orig_pressed(x, y, button, ...) end
end

local orig_released = love.mousereleased
love.mousereleased = function(x, y, button, ...)
    if swallow == button then
        swallow = nil
        return
    end
    if orig_released then return orig_released(x, y, button, ...) end
end

local orig_key = love.keypressed
love.keypressed = function(key, ...)
    if cfg.hotkeys then
        if key == "f6" then send("prev") elseif key == "f7" then send("toggle") elseif key == "f8" then send("next") end
    end
    if orig_key then return orig_key(key, ...) end
end

if SMODS and SMODS.update_hand_limit_text then
    local orig_limit_text = SMODS.update_hand_limit_text
    SMODS.update_hand_limit_text = function(...)
        local sp = G and G.GAME and G.GAME.starting_params
        if sp then
            sp.play_limit = sp.play_limit or 5
            sp.discard_limit = sp.discard_limit or 5
        end
        return orig_limit_text(...)
    end
end

log("geladen, Helper-Ordner: " .. ABS)
