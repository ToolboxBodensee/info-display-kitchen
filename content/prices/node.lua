gl.setup(1920, 1080)

util.resource_loader{
    "font.ttf";
    "background.png";
    "toolbox.png";
}

local Absatz = "absatz"

local preise = {
    {heading = "GETRÄNKE"},
    {"Wasser, Siebers, Glorietta, Spezi, Karamalz, Oettinger Limo, Mate Cola, Schwarzwald Limo, Mio Cola, Afri Cola, Bluna",    "1.00"},

    {"Fritz Cola, Proviant, Lemonaid, Bio Zisch, Mate, Bier, Radler, Seezüngle, Almdudler",      "1.50"},
    {"Charitea, Bundaberg, Despo 0.0, Elephant Bay",      "2.00"},
    {heading = "ESSEN"},
    {"Eis",   "2.00"},
    {"Tiefkühlgerichte",   "3.00"},
}

-- Wraps only between comma separated entries, so names never get split.
local function wrap(text, size, maxw)
    local toks = {}
    for tok in text:gmatch("[^,]+") do
        toks[#toks+1] = tok:match("^%s*(.-)%s*$")
    end
    local lines, cur = {}, nil
    for i, tok in ipairs(toks) do
        if i < #toks then tok = tok .. "," end
        local try = cur and (cur .. " " .. tok) or tok
        if cur and font:width(try, size) > maxw then
            lines[#lines+1] = cur
            cur = tok
        else
            cur = try
        end
    end
    if cur then lines[#lines+1] = cur end
    return lines
end

-- Lays out the table at `size`. Returns rows and total height.
local function layout(preise, size, area)
    local line_h = size * 1.08
    local row_gap = size * 0.4
    local price_w = 0
    for _, item in ipairs(preise) do
        if item ~= Absatz and not item.heading then
            price_w = math.max(price_w, font:width(item[2], size))
        end
    end
    local name_w = area.w - price_w - size
    local rows, yy, n_in_cat = {}, 0, 0
    for _, item in ipairs(preise) do
        if item == Absatz then
            yy = yy + size * 0.5
        elseif item.heading then
            local hs = size * 0.7
            if #rows > 0 then yy = yy + size * 0.4 end
            n_in_cat = 0
            rows[#rows+1] = {heading = item.heading, hsize = hs, y = area.y + yy}
            yy = yy + hs + row_gap
        else
            local lines = wrap(item[1], size, name_w)
            local h = size + (#lines - 1) * line_h
            n_in_cat = n_in_cat + 1
            rows[#rows+1] = {
                lines = lines, price = item[2], y = area.y + yy, h = h,
                band = n_in_cat % 2 == 1,
            }
            yy = yy + h + row_gap
        end
    end
    return rows, yy - row_gap, line_h, price_w
end

function Preisliste(preise, area, max_size, min_size)
    local rows, size, line_h, price_w
    for s = max_size, min_size, -2 do
        local r, h, lh, pw = layout(preise, s, area)
        rows, size, line_h, price_w = r, s, lh, pw
        if h <= area.h then break end
    end

    local rule = resource.create_colored_texture(1, 1, 1, 0.25)
    local band = resource.create_colored_texture(1, 1, 1, 0.07)
    local right = area.x + area.w
    local row, line, col, next_kaputt

    local function select_next()
        repeat row = rows[math.random(#rows)] until not row.heading
        line = math.random(#row.lines)
        col = math.random(math.max(1, #row.lines[line] - 1))
        next_kaputt = sys.now() + math.random() * 60 + 30
    end
    select_next()

    local function draw()
        if sys.now() > next_kaputt then select_next() end
        for n, r in ipairs(rows) do
            if r.heading then
                font:write(area.x, r.y, r.heading, r.hsize, 1,1,1,0.7)
                local ry = r.y + r.hsize + size * 0.05
                rule:draw(area.x - 15, ry, right + 15, ry + 2)
                goto continue
            end
            if r.band then
                local pad = size * 0.2
                band:draw(area.x - 15, r.y - pad, right + 15, r.y + r.h + pad)
            end
            for i, text in ipairs(r.lines) do
                if r == row and i == line and sys.now() > next_kaputt - 3 then
                    text = text:sub(1, col-1) .. text:sub(col+1, col+1) ..
                           text:sub(col, col) .. text:sub(col+2)
                end
                font:write(area.x, r.y + (i - 1) * line_h, text, size, 1,1,1,1)
            end
            local pw = font:width(r.price, size)
            font:write(right - pw, r.y, r.price, size, 1,1,1,1)
            ::continue::
        end
    end
    return { draw = draw }
end

local logo_shader = resource.create_shader([[
    uniform sampler2D Texture;
    varying vec2 TexCoord;
    uniform vec4 Color;
    void main() {
        vec4 texel = texture2D(Texture, TexCoord.st);
        // gl_FragColor = Color * texel;
        gl_FragColor = vec4(1.0, 1.0, 1.0, texel.a);
    }
]])

local distort_shader = resource.create_shader([[
    uniform sampler2D Texture;
    varying vec2 TexCoord;
    uniform vec4 Color;
    uniform float effect;
    void main() {
        vec2 uv = TexCoord.st;
        vec4 col;
        col.r = texture2D(Texture,vec2(uv.x+effect+sin(uv.y*20.0*effect)*0.02,uv.y)).r;
        col.g = texture2D(Texture,vec2(uv.x+effect+sin(uv.y*30.0*effect)*0.02,uv.y)).g;
        col.b = texture2D(Texture,vec2(uv.x-effect+sin(uv.y*40.0*effect)*0.02,uv.y)).b;
        col.a = texture2D(Texture,vec2(uv.x,uv.y)).a;
        gl_FragColor = Color * col;
    }
]])


local crt_shader = resource.create_shader([[
    uniform float time;
    uniform sampler2D Texture;
    varying vec2 TexCoord;
    uniform vec4 Color;

    void main(void)
    {
        vec2 q = TexCoord;
        vec2 uv = 0.5 + (q-0.5)*(0.98 + 0.0002*sin(0.2*time));

        vec3 oricol = texture2D(Texture,vec2(q.x,1.0-q.y)).xyz;
        vec3 col;

        float fnord = sin(time*1.0) * 0.001;
        col.r = texture2D(Texture,vec2(uv.x+fnord,uv.y)).x;
        col.g = texture2D(Texture,vec2(uv.x+0.000,uv.y)).y;
        col.b = texture2D(Texture,vec2(uv.x-fnord,uv.y)).z;

        col = clamp(col*0.5+0.5*col*col*1.2,0.0,1.0);
        col *= 0.5 + 0.5*16.0*uv.x*uv.y*(1.0-uv.x)*(1.0-uv.y);
        col *= vec3(0.8,1.0,0.7);
        col *= 0.9+0.1*sin(5.0*time+uv.y*1000.0);
        col *= 0.97+0.03*sin(3.0*time);

        float comp = smoothstep( 0.2, 0.5, sin(time) );

        gl_FragColor = vec4(col,1.0);
    }
]])



local source = (function()
    local lines = {}
    util.file_watch("info.txt", function(content)
        lines = {}
        for line in content:gmatch("[^\n]+") do
            lines[#lines+1] = line
        end
    end)
    return util.generator(function ()
        return lines
    end)
end)()


function Crapterm(source, x, y, size)
    local errors = "qwertyuiopasdfghjklzxcvbnm"
    local line
    local steps
    local step
    local next_step
    local speed = 0.3
    local cursor_base = sys.now()

    function next_line()
        line = source:next()
        step = 1
        steps = {}

        -- leerer anfang
        steps[#steps+1] = {
            "",
            1.0
        }

        -- hintippen
        for size = 1, #line do
            steps[#steps+1] = {
                line:sub(1, size),
                0.1 + math.random() * speed
            }
        end

        -- tippfehler einfuegen
        local mistakes = math.random(3)
        for _ = 1,mistakes do
            local off = math.random(#steps-1)
            local base_string, delay = unpack(steps[off])
            local err_off = math.random(#errors)
            local err = errors:sub(err_off, err_off)
            table.insert(steps, off+1, {
                base_string .. err,
                0.1 + math.random() * speed
            })
            table.insert(steps, off+2, {
                base_string,
                0.1 + math.random() * speed / 2
            })
        end
        -- ergebnis laenger stehen lassen
        steps[#steps-1][2] = 3.0

        -- loeschen
        for size = #line-1, 1, -1 do
            steps[#steps+1] = {
                line:sub(1, size),
                0.1 + math.random() * speed / 5
            }
        end

        -- leeres ende
        steps[#steps+1] = {
            "",
            1.0
        }
        next_step = sys.now() + steps[1][2]
    end

    next_line()

    function draw()
        local current, delay = unpack(steps[step])
        current = "> " .. current
        local cursor_x = font:write(x, y, current, size, 1,1,1,1)
        cursor_x = cursor_x + 40
        if ((sys.now() - cursor_base)*2) % 2 < 1 then
            font:write(cursor_x, y, "_", size, 1,1,1,1)
        end

        if sys.now() > next_step then
            step = step + 1
            if step > #steps then
                next_line()
            end
            next_step = sys.now() + delay
            cursor_base = sys.now()
        end
    end

    return {
        draw = draw;
    }
end

local term = Crapterm(source, 35, 950, 100)
local preisliste = Preisliste(preise, {x = 35, y = 40, w = WIDTH - 70, h = HEIGHT - 80}, 60, 24)

local countdown = sys.now() + math.random() * 10

function node.render()
    background:draw(0,0,WIDTH,HEIGHT)
    preisliste:draw()
    -- term:draw()
    -- logo_shader:use()
    --     gl.perspective(50,
    --         WIDTH/2+60, HEIGHT/2+45, -WIDTH/1.38,
    --         WIDTH/2+60, HEIGHT/2+45, 0
    --     )
    --     gl.pushMatrix()
    --         gl.translate(1250, 0)
    --         gl.rotate(10, 0, 0, 1)
    --         gl.translate(0, 100)
    --         -- gl.rotate((sys.now()*100) % 180-90, 1, 0, 0)
    --         gl.rotate(math.sin(sys.now()/2.0)*15, 1, 0, 0)
    --         gl.rotate(math.sin(sys.now()/5.0)*8, 0, 1, 0)
    --         gl.translate(0, -100)
    --         util.draw_correct(toolbox, 0, 0, 600, 200, 1,0,0,1)
    --     gl.popMatrix()
    --     gl.ortho()
    -- logo_shader:deactivate()
    -- util.post_effect(crt_shader, {
    --    time = sys.now(),
    --})

    -- local remaining = countdown - sys.now()
    -- if remaining < 0 then
    --     countdown = sys.now() + math.random() * 10
    -- elseif remaining < 0.3 then
    --     util.post_effect(distort_shader, {
    --         effect = math.random() * math.sin(sys.now()) * 200
    --     })
    -- end
end
