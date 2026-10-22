--[[
	Feral UI Library  (combined)
	Look  : original Feral library (Gotham fonts, accent header lines, checkbox toggles, glow, custom cursor)
	Layout: 650x450 window, sub tabs, stacked sections. Top bar and sidebar are identical to the original Feral.

	local Library = loadstring(...)()
	local Window  = Library:Window({
		Title = "Feral Hub" (sidebar), Brand = "Feral" (accent word in top bar), Desc = "v1.0" (next to it), Logo = "rbxassetid://...",
		ToggleKey = Enum.KeyCode.RightShift,   -- default RightShift
		Cursor = true,                         -- custom cursor while the window is open (false = off)
		OnSettings = function() end,           -- optional gear button in the top bar
	})
	(Library:CreateMain(cfg) is the same thing.)

	local Tab     = Window:AddTab("Main")                          -- sidebar tabs have no icons
	local SubTab  = Tab:AddSubTab("Farming")
	local Section = SubTab:AddSection("Auto Farm")                 -- sections stack under each other

	Old-API shortcut (one tab + one sub tab, sections auto-balance between the columns):
	local Page    = Window:CreatePage("Main", "Main Tab")
	local Section = Page:CreateSection("Section name")

	Every control takes ({ ... }, optionalCallback) and exists as AddX and CreateX:
	Section:AddToggle     ({ Title, Description, Default, Flag, Callback, Color, ColorFlag, ColorCallback })  -> { Set, Get, Colorpicker }
	Section:AddButton     ({ Title, Callback })
	Section:AddLabel      ({ Title })                                                              -> { SetText, SetColor }
	Section:AddTextbox    ({ Title, Default, Placeholder, Icon, Flag, Callback })                    -> { Set, Get }   (AddBox / CreateBox)
	Section:AddTextIndicator({ Title, Default, Placeholder, Icon, Flag })                            -> { Set, Get }
	Section:AddSlider     ({ Title, Min, Max, Default, Decimals, Prefix, Suffix, Flag, Callback })  -> { Set, Get }
	Section:AddDropdown   ({ Title, Options, Default, Multi, Flag, Callback })                      -> { Set, Get, Refresh }
	Section:AddBind       ({ Title, Default = Enum.KeyCode.X, ToggleUI = true, Flag, Callback })    -> { Set, Get }
	Section:AddColorpicker({ Title, Default = Color3, Flag, Callback })                             -> { Set, Get }
	Section:AddConfigManager()                                                                      (one per script)

	obj:Set(value, silent)  -> fires the callback unless silent == true.
	Library.Flags[flag]     -> raw value of every control (no Flag given = one is generated from the names).
	Library.Objects[flag]   -> the control object itself.
	Library:GetConfig() / Library:LoadConfig(json) / Library:LoadAutoLoad()
	Library:Notify(Title, Desc, Duration) / Library:CreateNoti({ Title, Desc, ShowTime })
	Library:SetAccent(Color3) / Library:Exit()
	Window:SetVisible(bool) / Window:Toggle() / Window:Destroy() / Tab:Select() / SubTab:Select()
]]

if getgenv and getgenv().Library and getgenv().Library.Exit then
	pcall(function() getgenv().Library:Exit() end)
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local Library = {
	Alive = true,
	Directory = "feral",
	Folders = { Assets = "/Assets", Configs = "/Configs" },
	Animation = { Time = 0.3, Style = "Exponential", Direction = "Out" },
	Theme = {
		Border      = Color3.fromRGB(40, 40, 40),
		Bg1         = Color3.fromRGB(30, 30, 30),
		Bg2         = Color3.fromRGB(45, 45, 45),
		Bg3         = Color3.fromRGB(24, 24, 24),
		Accent      = Color3.fromRGB(90, 160, 255),
		Text        = Color3.fromRGB(220, 220, 220),
		Placeholder = Color3.fromRGB(150, 150, 150),
		Desc        = Color3.fromRGB(180, 180, 180),
		Icon        = Color3.fromRGB(200, 200, 200),
		SliderLine  = Color3.fromRGB(60, 60, 60),
		T1 = 0.25, T2 = 0.5, T3 = 0.1,
	},
	Assets = {
		Slice    = "rbxassetid://8068653048",
		Logo     = "rbxassetid://134323059585110",
		Gear     = "rbxassetid://7397332215",
		Search   = "rbxassetid://8154282545",
		Checkbox = "rbxassetid://4552505888",
		Check    = "rbxassetid://4555411759",
		Arrow    = "rbxassetid://6954383209",
		Cursor   = "rbxassetid://112328791874559",
	},
	Windows = {},
	Flags = {},       -- flag -> raw value (what the config saves)
	SetFlags = {},    -- flag -> function(value) that sets a control silently
	Objects = {},     -- flag -> control object
	Connections = {},
	Keybind = nil,    -- optional default window toggle key (Enum.KeyCode)
}

local T = Library.Theme
local A = Library.Assets

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
local function getParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	local ok2 = pcall(function() return game:GetService("CoreGui").Name end)
	if ok2 then return game:GetService("CoreGui") end
	return player:WaitForChild("PlayerGui")
end

local function new(class, props, kids)
	local i = Instance.new(class)
	-- keep all UI text in English: stop Roblox from auto-translating it
	if i:IsA("GuiBase2d") then i.AutoLocalize = false end
	for k, v in pairs(props or {}) do i[k] = v end
	for _, c in ipairs(kids or {}) do c.Parent = i end
	return i
end

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end

local function stroke(color, thickness)
	return new("UIStroke", { Color = color, Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function text(parent, props)
	local p = {
		BackgroundTransparency = 1, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 14,
		TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = parent,
	}
	for k, v in pairs(props) do p[k] = v end
	return new("TextLabel", p)
end

local function tween(o, props, t)
	TweenService:Create(o, TweenInfo.new(t or T.T1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function enumOr(enum, name, fallback)
	local ok, v = pcall(function() return enum[name] end)
	if ok and v then return v end
	return fallback
end

-- slower tween using Library.Animation (window slide in / out); returns the tween
local function slow(o, props)
	local a = Library.Animation
	local tw = TweenService:Create(o, TweenInfo.new(a.Time, enumOr(Enum.EasingStyle, a.Style, Enum.EasingStyle.Exponential),
		enumOr(Enum.EasingDirection, a.Direction, Enum.EasingDirection.Out)), props)
	tw:Play()
	return tw
end

local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(Library.Connections, c)
	return c
end
function Library:Connect(signal, fn) return connect(signal, fn) end

local function noop() end

local function draggable(handle, target, conn, canDrag)
	local dragging, start, startPos
	handle.InputBegan:Connect(function(i)
		if canDrag and not canDrag() then return end
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, start, startPos = true, i.Position, target.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	conn(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - start
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

local function overFrame(f)
	local m = UIS:GetMouseLocation() -- ScreenGuis use IgnoreGuiInset, so this matches AbsolutePosition
	local p, s = f.AbsolutePosition, f.AbsoluteSize
	return m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y
end

local function keyName(k)
	if not k then return "None" end
	local s = tostring(k):gsub("Enum%.KeyCode%.", ""):gsub("Enum%.UserInputType%.", "")
	s = s:gsub("MouseButton", "MB")
	return s
end

local function toKey(v)
	if typeof(v) == "EnumItem" then return v end
	if type(v) == "string" then
		local n = (v:gsub("^Enum%.KeyCode%.", ""))
		n = (n:gsub("^Enum%.UserInputType%.", ""))
		local ok, r = pcall(function() return Enum.KeyCode[n] end)
		if ok and r then return r end
		ok, r = pcall(function() return Enum.UserInputType[n] end)
		if ok and r then return r end
	end
	return nil
end

-- keys that can't type into a TextBox, so a focused TextBox must not block them
local function isNonTypingKey(k)
	if typeof(k) ~= "EnumItem" then return true end
	if k.EnumType ~= Enum.KeyCode then return true end
	local n = k.Name
	return n:match("^F%d+$") ~= nil or n:find("Shift") ~= nil or n:find("Control") ~= nil or n:find("Alt") ~= nil
		or n == "Insert" or n == "Delete" or n == "Home" or n == "End" or n == "PageUp" or n == "PageDown"
		or n == "CapsLock" or n == "Tab" or n == "Escape"
end

local function hexToColor(hex)
	hex = tostring(hex):gsub("#", "")
	if #hex ~= 6 then return nil end
	local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	if r and g and b then return Color3.fromRGB(r, g, b) end
	return nil
end

-- accent color registry (so Library:SetAccent recolors everything live)
local accentFns = {}
local function onAccent(fn)
	table.insert(accentFns, fn)
	fn(T.Accent)
end
local function accent(inst, prop)
	onAccent(function(c) inst[prop] = c end)
end

function Library:SetAccent(color)
	T.Accent = color
	for _, fn in ipairs(accentFns) do pcall(fn, color) end
end
function Library:ChangeTheme(name, color)
	if name == "Accent" then return Library:SetAccent(color) end
	if T[name] ~= nil then T[name] = color end
end

local function ensureFolders()
	pcall(function()
		if not isfolder(Library.Directory) then makefolder(Library.Directory) end
		for _, f in pairs(Library.Folders) do
			local p = Library.Directory .. f
			if not isfolder(p) then makefolder(p) end
		end
	end)
end

-- Registers a control so configs can save/load it.
-- Give a control an explicit `Flag = "Id"`, or one is generated from "<tab>/<sub tab>/<section>/<title>".
local function register(fprefix, cfg, obj, kind, flagValue)
	obj.Type = kind
	local flag = cfg.Flag
	if not flag then
		local base = fprefix .. tostring(cfg.Title or kind)
		flag = base
		local n = 1
		while Library.Objects[flag] do
			n = n + 1
			flag = base .. "#" .. n
		end
	end
	obj.Flag = flag
	Library.Objects[flag] = obj
	Library.SetFlags[flag] = function(v) obj:Set(v, true) end
	Library.Flags[flag] = flagValue
	return obj
end

local function pushFlag(obj, v)
	if obj.Flag then Library.Flags[obj.Flag] = v end
end

--------------------------------------------------------------------
-- Config
--------------------------------------------------------------------
function Library:GetConfig()
	local out = {}
	for flag, value in pairs(Library.Flags) do
		if typeof(value) == "Color3" then out[flag] = "#" .. value:ToHex() else out[flag] = value end
	end
	local ok, res = pcall(function() return HttpService:JSONEncode(out) end)
	if not ok then
		warn("[Library] Failed to encode config:\n" .. tostring(res))
		return nil
	end
	return res
end

function Library:LoadConfig(json)
	local ok, decoded = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok then
		warn("[Library] Failed to decode config:\n" .. tostring(decoded))
		return false
	end
	for flag, value in pairs(decoded) do
		local setter = Library.SetFlags[flag]
		if setter then
			local obj = Library.Objects[flag]
			if obj and obj.Type == "Colorpicker" and type(value) == "string" then value = hexToColor(value) end
			if value ~= nil then
				local sok, err = pcall(setter, value)
				if not sok then warn("[Library] Could not load '" .. tostring(flag) .. "': " .. tostring(err)) end
			end
		end
	end
	return true
end

function Library:GetConfigsList(Element)
	local list = {}
	pcall(function()
		for _, f in ipairs(listfiles(Library.Directory .. Library.Folders.Configs)) do
			local name = tostring(f):match("([^/\\]+)%.json$")
			if name then table.insert(list, name) end
		end
	end)
	if Element and Element.Refresh then Element:Refresh(list) end
	return list
end

function Library:LoadAutoLoad()
	local ok, name = pcall(function()
		local p = Library.Directory .. "/AutoLoad.json"
		if isfile(p) then return readfile(p) end
	end)
	if not ok or not name or name == "" then return false end
	name = (name:gsub("%s+$", ""))
	local path = Library.Directory .. Library.Folders.Configs .. "/" .. name .. ".json"
	local ok2, data = pcall(function() if isfile(path) then return readfile(path) end end)
	if ok2 and data then return Library:LoadConfig(data) end
	return false
end

--------------------------------------------------------------------
-- Custom cursor (only active while a Feral window is open)
--------------------------------------------------------------------
local Cursor = { Holders = {} }
local cursorGui, cursorConn, savedIconEnabled

function Cursor.Stop()
	if cursorConn then cursorConn:Disconnect() cursorConn = nil end
	if cursorGui then cursorGui:Destroy() cursorGui = nil end
	if savedIconEnabled ~= nil then
		UIS.MouseIconEnabled = savedIconEnabled -- back to the normal Roblox cursor
		savedIconEnabled = nil
	end
end

function Cursor.Start()
	if cursorGui then return end
	savedIconEnabled = UIS.MouseIconEnabled
	local parent = getParent()
	local old = parent:FindFirstChild("FeralCustomCursor")
	if old then old:Destroy() end
	cursorGui = new("ScreenGui", { Name = "FeralCustomCursor", IgnoreGuiInset = true, ResetOnSpawn = false,
		DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Global, Parent = parent })
	local img = new("ImageLabel", { Name = "Cursor", BackgroundTransparency = 1, Image = A.Cursor, Size = UDim2.fromOffset(32, 32),
		ZIndex = 2147483647, Parent = cursorGui })
	UIS.MouseIconEnabled = false
	cursorConn = RunService.RenderStepped:Connect(function()
		local pos = UIS:GetMouseLocation()
		img.Position = UDim2.fromOffset(pos.X, pos.Y)
		if UIS.MouseIconEnabled then UIS.MouseIconEnabled = false end -- keep Roblox cursor hidden
	end)
end

function Cursor.Set(key, on)
	Cursor.Holders[key] = on and true or nil
	if next(Cursor.Holders) ~= nil then Cursor.Start() else Cursor.Stop() end
end

--------------------------------------------------------------------
-- Notifications (stacked; the "Example" card shown while the window is open can be dragged to move them)
--------------------------------------------------------------------
local notiGui, notiHolder
local notiCount = 0

local function ensureNoti()
	if notiGui and notiGui.Parent then return end
	local parent = getParent()
	local old = parent:FindFirstChild("Feral Notification")
	if old then old:Destroy() end
	notiGui = new("ScreenGui", { Name = "Feral Notification", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = parent })
	notiHolder = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 40), Size = UDim2.new(0, 260, 1, -50),
		BackgroundTransparency = 1, Parent = notiGui },
		{ new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
end

local function buildNotiCard(title, desc, closable)
	local outer = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		ClipsDescendants = true })
	local card = new("Frame", { Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.Bg3, BorderSizePixel = 0, Active = true, Parent = outer },
		{ corner(4), stroke(T.Border, 1.5), new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })

	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1, Parent = card })
	new("ImageLabel", { Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(25, 25), BackgroundTransparency = 1, Image = A.Logo, Parent = head })
	local tl = text(head, { Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -70, 1, 0), Text = tostring(title or "Feral"),
		TextTruncate = Enum.TextTruncate.AtEnd })
	accent(tl, "TextColor3")

	local close
	if closable then
		close = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "x", TextSize = 16, TextColor3 = T.Icon, Parent = head })
		close.MouseEnter:Connect(function() tween(close, { TextColor3 = T.Accent }, T.T3) end)
		close.MouseLeave:Connect(function() tween(close, { TextColor3 = T.Icon }, T.T3) end)
	end

	local body = text(card, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextWrapped = true,
		TextColor3 = T.Desc, Text = tostring(desc or "") })
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = body })
	return outer, card, close
end

function Library:CreateNoti(cfg)
	cfg = cfg or {}
	ensureNoti()
	local outer, card, close = buildNotiCard(cfg.Title or "Feral", cfg.Desc or cfg.Description or "", true)
	notiCount = notiCount + 1
	outer.LayoutOrder = notiCount
	outer.Parent = notiHolder

	card.Position = UDim2.new(1, 10, 0, 0)
	tween(card, { Position = UDim2.new(0, 0, 0, 0) }, T.T1)

	local closed = false
	local function dismiss()
		if closed then return end
		closed = true
		tween(card, { Position = UDim2.new(1, 10, 0, 0) }, T.T1)
		task.wait(T.T1)
		outer:Destroy()
	end
	close.MouseButton1Click:Connect(function() task.spawn(dismiss) end)
	task.delay(cfg.ShowTime or cfg.Duration or 5, function() task.spawn(dismiss) end)
	return { Close = dismiss }
end

function Library:Notify(Title, Desc, Duration)
	return Library:CreateNoti({ Title = Title, Desc = Desc, ShowTime = Duration or 3 })
end

function Library:Exit()
	Library.Alive = false
	for _, c in ipairs(Library.Connections) do pcall(function() c:Disconnect() end) end
	Library.Connections = {}
	for _, w in ipairs(Library.Windows) do pcall(function() w.Gui:Destroy() end) end
	Library.Windows = {}
	Cursor.Stop()
	if notiGui then pcall(function() notiGui:Destroy() end) notiGui = nil end
	if getgenv and getgenv().Library == Library then getgenv().Library = nil end
end

--------------------------------------------------------------------
-- Window
--------------------------------------------------------------------
function Library:Window(cfg)
	if type(cfg) ~= "table" then cfg = {} end
	Library.Flags, Library.SetFlags, Library.Objects = {}, {}, {}
	Library._ConfigManagerMade = false
	for i = #accentFns, 1, -1 do accentFns[i] = nil end
	ensureFolders()

	local parent = getParent()
	local old = parent:FindFirstChild("Feral GUI")
	if old then old:Destroy() end

	-- every global-signal connection made for this window, so Window:Destroy() can drop them
	local winConns = {}
	local function wconnect(signal, fn)
		local c = connect(signal, fn)
		table.insert(winConns, c)
		return c
	end

	local gui = new("ScreenGui", { Name = "Feral GUI", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = parent })

	local Window = { Gui = gui, Tabs = {}, Open = true, SelectedTab = nil }
	local winTitle = tostring(cfg.Title or cfg.Brand or "Feral Hub")
	local gameName = tostring(cfg.GameName or cfg.Desc or "")
	local logo = cfg.Logo or A.Logo
	local useCursor = cfg.Cursor ~= false

	local OPEN_POS = UDim2.fromScale(0.5, 0.5)
	local CLOSED_POS = UDim2.new(0.5, 0, 1.4, 0)

	local main = new("Frame", { Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5), Position = OPEN_POS,
		Size = UDim2.fromOffset(650, 450), BackgroundTransparency = 1, Parent = gui })

	local glow = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 30, 1, 30),
		BackgroundTransparency = 1, Image = A.Slice, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(15, 15, 175, 175),
		SliceScale = 1.3, ZIndex = 0, Parent = main })
	accent(glow, "ImageColor3")

	local body = new("Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Bg1, BorderSizePixel = 0, ZIndex = 1,
		Parent = main }, { corner(4) })

	----------------------------------------------------------------
	-- Top bar (same as the original Feral): logo + "Brand Desc" + optional settings gear
	----------------------------------------------------------------
	local function rgbTag(c)
		return string.format("rgb(%d,%d,%d)", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
	end
	local brand = tostring(cfg.Brand or "Feral")
	local descText = tostring(cfg.Desc or cfg.GameName or "")

	local top = new("Frame", { Name = "TopMain", Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, Parent = body })
	draggable(top, main, wconnect)
	new("ImageLabel", { Position = UDim2.fromOffset(5, 0), Size = UDim2.fromOffset(25, 25), BackgroundTransparency = 1, Image = logo, Parent = top })
	local titleLabel = new("TextLabel", { Position = UDim2.fromOffset(35, 0), Size = UDim2.new(1, -70, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, RichText = true, TextSize = 16, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = top })
	onAccent(function(c)
		titleLabel.Text = string.format('<font color="%s">%s</font> %s', rgbTag(c), brand, descText)
	end)

	if cfg.OnSettings then
		local settings = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(30, 30),
			BackgroundTransparency = 1, Parent = top })
		local gear = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, -10),
			BackgroundTransparency = 1, Image = A.Gear, ImageColor3 = T.Icon, Parent = settings })
		local sb = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = settings })
		sb.MouseEnter:Connect(function() tween(gear, { ImageColor3 = T.Accent }, T.T3) end)
		sb.MouseLeave:Connect(function() tween(gear, { ImageColor3 = T.Icon }, T.T3) end)
		sb.MouseButton1Click:Connect(function() task.spawn(cfg.OnSettings) end)
	end

	----------------------------------------------------------------
	-- Sidebar (same as the original Feral: 180px, title, tabs with the accent line) + content card
	----------------------------------------------------------------
	local side = new("Frame", { Name = "Sidebar", Position = UDim2.fromOffset(5, 30), Size = UDim2.fromOffset(180, 416), BackgroundColor3 = T.Bg1,
		BorderSizePixel = 0, Parent = body }, { corner(4), stroke(T.Border, 1.5) })
	text(side, { Position = UDim2.fromOffset(5, 0), Size = UDim2.new(1, 0, 0, 25), Text = tostring(cfg.Title or "Feral") })
	local tabScroll = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -5, 1, -30), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 5, Active = true, CanvasSize = UDim2.new(), Parent = side })
	local tabLayout = new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5), Parent = tabScroll })
	tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		tabScroll.CanvasSize = UDim2.fromOffset(0, tabLayout.AbsoluteContentSize.Y + 5)
	end)

	local card = new("Frame", { Name = "Content", Position = UDim2.fromOffset(190, 30), Size = UDim2.fromOffset(456, 416), BackgroundColor3 = T.Bg1,
		BorderSizePixel = 0, Parent = body }, { corner(4) })

	-- search box (filters the sections of the open sub tab by name)
	local sbox = new("Frame", { Name = "Search", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 5), Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = T.Bg2, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 5, Parent = card }, { corner(2) })
	local sicon = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1, Image = A.Search, ImageColor3 = T.Icon, ZIndex = 5, Parent = sbox })
	local sbtn = new("TextButton", { Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Text = "", ZIndex = 6, Parent = sbox })
	local sinput = new("TextBox", { Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -30, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, Text = "", TextSize = 14, PlaceholderText = "Search Section name", PlaceholderColor3 = T.Placeholder,
		TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 5, Parent = sbox })
	local searchOpen = false
	sbtn.MouseEnter:Connect(function() tween(sicon, { ImageColor3 = T.Accent }, T.T3) end)
	sbtn.MouseLeave:Connect(function() tween(sicon, { ImageColor3 = T.Icon }, T.T3) end)
	sbtn.MouseButton1Click:Connect(function()
		searchOpen = not searchOpen
		tween(sbox, { Size = searchOpen and UDim2.fromOffset(190, 20) or UDim2.fromOffset(20, 20) }, T.T2)
		if searchOpen then sinput:CaptureFocus() else sinput.Text = "" end
	end)

	local function applySearch()
		local q = sinput.Text:lower()
		local tab = Window.SelectedTab
		local sub = tab and tab.SelectedSub
		if not sub then return end
		for _, s in ipairs(sub.Sections) do
			s.Frame.Visible = q == "" or s.Title:lower():find(q, 1, true) ~= nil
		end
	end
	sinput:GetPropertyChangedSignal("Text"):Connect(applySearch)

	----------------------------------------------------------------
	-- Toggle key: InputBegan (ignores `gp`, since Roblox shift-lock marks RightShift as processed)
	-- plus a polling fallback via IsKeyDown, in case the game/executor swallows the event.
	----------------------------------------------------------------
	local toggleKey = toKey(cfg.ToggleKey) or toKey(Library.Keybind) or Enum.KeyCode.RightShift
	local lastToggle = 0
	local rebinding = false -- true while a "Toggle UI" bind is waiting for a new key
	local rebindAt = 0
	local wasDown = false

	local function setToggleKey(k)
		k = toKey(k)
		if not k then return end
		toggleKey = k
		-- don't let the press that picked the key (or a held key) toggle the UI
		wasDown = typeof(k) == "EnumItem" and k.EnumType == Enum.KeyCode and UIS:IsKeyDown(k)
		lastToggle = os.clock()
	end
	local function pressToggle()
		if rebinding and os.clock() - rebindAt < 8 then return end -- failsafe: never stay locked
		if os.clock() - lastToggle < 0.15 then return end -- both paths can fire for one press
		if UIS:GetFocusedTextBox() and not isNonTypingKey(toggleKey) then return end
		lastToggle = os.clock()
		Window:SetVisible(not Window.Open)
	end
	wconnect(UIS.InputBegan, function(i)
		if i.KeyCode == toggleKey or i.UserInputType == toggleKey then pressToggle() end
	end)
	wconnect(RunService.RenderStepped, function()
		local down = typeof(toggleKey) == "EnumItem" and toggleKey.EnumType == Enum.KeyCode and UIS:IsKeyDown(toggleKey)
		if down and not wasDown then pressToggle() end
		wasDown = down
	end)

	----------------------------------------------------------------
	-- Draggable notification demo
	----------------------------------------------------------------
	local demoCard
	if cfg.NotifyDemo ~= false then
		ensureNoti()
		local demoInner
		demoCard, demoInner = buildNotiCard("Example", "Drag me to reposition notifications", false)
		demoCard.Name = "NotificationDemo"
		demoCard.LayoutOrder = -1000
		demoCard.Parent = notiHolder
		draggable(demoInner, notiHolder, wconnect, function() return Window.Open end)
	end

	-- custom cursor follows the window: shown while open, normal Roblox cursor when closed/unloaded
	local cursorKey = {}
	Cursor.Set(cursorKey, useCursor)

	function Window:SetVisible(v)
		v = v and true or false
		if self.Open == v then return end
		self.Open = v
		Cursor.Set(cursorKey, v and useCursor)
		if demoCard then demoCard.Visible = v end
		if v then
			main.Visible = true
			main.Position = CLOSED_POS
			slow(main, { Position = OPEN_POS })
		else
			local tw = slow(main, { Position = CLOSED_POS })
			tw.Completed:Connect(function() if not Window.Open then main.Visible = false end end)
		end
	end
	function Window:Toggle(state)
		if state == nil then state = not self.Open end
		self:SetVisible(state)
	end
	function Window:SetToggleKey(k) setToggleKey(k) end
	function Window:Notify(t, d, dur) return Library:Notify(t, d, dur) end
	function Window:Destroy()
		for _, c in ipairs(winConns) do pcall(function() c:Disconnect() end) end
		winConns = {}
		Cursor.Set(cursorKey, false)
		if demoCard then demoCard:Destroy() end
		gui:Destroy()
		for i, w in ipairs(Library.Windows) do
			if w == Window then table.remove(Library.Windows, i) break end
		end
	end

	----------------------------------------------------------------
	-- Colorpicker popup (used by Toggle's Color option and Section:AddColorpicker)
	----------------------------------------------------------------
	local function isClick(i)
		return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
	end

	local function buildPicker(square, startColor, onChange)
		local CP = { Value = startColor, IsOpen = false }
		local h, s, v = startColor:ToHSV()

		local popup = new("Frame", { Name = "ColorpickerPopup", Size = UDim2.fromOffset(180, 150), BackgroundColor3 = T.Bg3, BorderSizePixel = 0,
			Visible = false, Active = true, ZIndex = 50, Parent = gui }, { corner(4), stroke(T.Border, 1.5) })
		local scale = new("UIScale", { Scale = 0, Parent = popup })

		local sv = new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(130, 130), BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			BorderSizePixel = 0, Active = true, ZIndex = 51, Parent = popup }, { corner(4) })
		new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 52, Parent = sv },
			{ corner(4), new("UIGradient", { Transparency = NumberSequence.new(0, 1) }) })
		new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 53, Parent = sv },
			{ corner(4), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }) })
		local svm = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(8, 8), BackgroundTransparency = 1, BorderSizePixel = 0,
			ZIndex = 54, Parent = sv }, { corner(4), stroke(Color3.new(1, 1, 1), 2) })

		local hue = new("Frame", { Position = UDim2.new(1, -30, 0, 10), Size = UDim2.fromOffset(20, 130), BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0, Active = true, ZIndex = 51, Parent = popup },
			{ corner(4), new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)), ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)), ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)) }) }) })
		local hm = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 4, 0, 4), BackgroundTransparency = 1, BorderSizePixel = 0,
			ZIndex = 54, Parent = hue }, { corner(2), stroke(Color3.new(1, 1, 1), 2) })

		local function update(silent)
			local color = Color3.fromHSV(h, s, v)
			CP.Value = color
			square.BackgroundColor3 = color
			sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svm.Position = UDim2.fromScale(s, 1 - v)
			hm.Position = UDim2.fromScale(0.5, h)
			pushFlag(CP, color)
			if not silent then task.spawn(onChange or noop, color) end
		end

		local svDrag, hueDrag = false, false
		local function fromMouse()
			local m = UIS:GetMouseLocation()
			if svDrag then
				local p, sz = sv.AbsolutePosition, sv.AbsoluteSize
				s = math.clamp((m.X - p.X) / math.max(sz.X, 1), 0, 1)
				v = 1 - math.clamp((m.Y - p.Y) / math.max(sz.Y, 1), 0, 1)
				update()
			elseif hueDrag then
				local p, sz = hue.AbsolutePosition, hue.AbsoluteSize
				h = math.clamp((m.Y - p.Y) / math.max(sz.Y, 1), 0, 1)
				update()
			end
		end
		sv.InputBegan:Connect(function(i) if isClick(i) then svDrag = true fromMouse() end end)
		hue.InputBegan:Connect(function(i) if isClick(i) then hueDrag = true fromMouse() end end)
		wconnect(UIS.InputChanged, function(i)
			if (svDrag or hueDrag) and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromMouse() end
		end)
		wconnect(UIS.InputEnded, function(i)
			if isClick(i) then svDrag, hueDrag = false, false end
		end)

		function CP:Open()
			self.IsOpen = true
			local m = UIS:GetMouseLocation()
			local vp = workspace.CurrentCamera.ViewportSize
			popup.Position = UDim2.fromOffset(math.clamp(m.X, 0, math.max(0, vp.X - 180)), math.clamp(m.Y, 0, math.max(0, vp.Y - 150)))
			popup.Visible = true
			scale.Scale = 0
			slow(scale, { Scale = 1 })
		end
		function CP:Close()
			self.IsOpen = false
			local tw = slow(scale, { Scale = 0 })
			tw.Completed:Connect(function() if not CP.IsOpen then popup.Visible = false end end)
		end
		function CP:Toggle() if self.IsOpen then self:Close() else self:Open() end end
		function CP:Get() return self.Value end
		function CP:Set(value, silent)
			local c = value
			if type(value) == "string" then c = hexToColor(value) end
			if typeof(c) ~= "Color3" then return end
			h, s, v = c:ToHSV()
			update(silent)
		end

		local clicker = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 6, Parent = square })
		clicker.MouseButton1Click:Connect(function() CP:Toggle() end)
		wconnect(UIS.InputBegan, function(i)
			if not isClick(i) or not CP.IsOpen then return end
			if overFrame(popup) or overFrame(square) then return end
			CP:Close()
		end)

		update(true)
		return CP
	end

	----------------------------------------------------------------
	-- Controls
	----------------------------------------------------------------
	local function buildControls(Section, sec, fprefix)
		local order = 0
		local function nextOrder() order = order + 1 return order end

		local function norm(c, cb)
			if type(c) ~= "table" then c = { Title = tostring(c) } end
			return c, cb or c.Callback or noop
		end

		-- a Bg1 row with the given height
		local function makeRow(h, name)
			local frame = new("Frame", { Name = name, Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = sec })
			local bg = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, 0),
				BackgroundColor3 = T.Bg1, BorderSizePixel = 0, Parent = frame }, { corner(4) })
			return frame, bg
		end

		----------------------------------------------------------------
		-- Toggle (checkbox look, optional colorpicker square)
		----------------------------------------------------------------
		function Section:AddToggle(c, cb)
			c, cb = norm(c, cb)
			local Toggle = { Title = c.Title, Value = c.Default and true or false }
			local frame = new("Frame", { Name = "Toggle", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
				LayoutOrder = nextOrder(), Parent = sec }, { new("UIPadding", { PaddingBottom = UDim.new(0, 6) }) })
			local tf = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1, -10, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = frame })
			new("Frame", { Size = UDim2.new(1, 0, 1, 6), BackgroundColor3 = T.Bg1, BorderSizePixel = 0, Parent = tf }, { corner(4) })
			local hasDesc = c.Description and c.Description ~= ""
			local labelW = c.Color and -75 or -50
			text(tf, { Position = UDim2.fromOffset(10, hasDesc and 0 or 5), Size = UDim2.new(1, labelW, 0, 20), AutomaticSize = Enum.AutomaticSize.Y,
				Font = Enum.Font.GothamBlack, Text = tostring(c.Title or "Toggle"), TextTruncate = Enum.TextTruncate.AtEnd })
			if hasDesc then
				text(tf, { Position = UDim2.fromOffset(15, 20), Size = UDim2.new(1, labelW, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					Font = Enum.Font.GothamBlack, Text = c.Description, TextSize = 13, TextWrapped = true, TextColor3 = T.Desc })
			end
			local checkbox = new("ImageLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 3), Size = UDim2.fromOffset(25, 25),
				BackgroundTransparency = 1, Image = A.Checkbox, ZIndex = 3, Parent = tf })
			accent(checkbox, "ImageColor3")
			local check = new("ImageLabel", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(), BackgroundTransparency = 1,
				Image = A.Check, ImageColor3 = T.Text, ZIndex = 3, Parent = checkbox })
			local click = new("TextButton", { Size = UDim2.new(1, 0, 1, 6), BackgroundTransparency = 1, Text = "", ZIndex = 4, Parent = tf })

			local function visual(v)
				tween(check, v and { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) }
					or { Size = UDim2.new(), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1) })
			end
			function Toggle:Set(val, silent)
				self.Value = val and true or false
				visual(self.Value)
				pushFlag(self, self.Value)
				if not silent then task.spawn(cb, self.Value) end
			end
			function Toggle:Get() return self.Value end
			click.MouseButton1Click:Connect(function() Toggle:Set(not Toggle.Value) end)
			if Toggle.Value then visual(true) end

			register(fprefix, c, Toggle, "Toggle", Toggle.Value)

			if c.Color then
				local sq = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -35, 0.5, 3), Size = UDim2.fromOffset(20, 16),
					BackgroundColor3 = c.Color, BorderSizePixel = 0, ZIndex = 5, Parent = tf }, { corner(4), stroke(T.Border, 1.5) })
				local cp = buildPicker(sq, c.Color, c.ColorCallback)
				register(fprefix, { Flag = c.ColorFlag or (Toggle.Flag .. "_Color"), Title = tostring(c.Title) .. " Color" }, cp, "Colorpicker", cp.Value)
				Toggle.Colorpicker = cp
			end
			return Toggle
		end

		----------------------------------------------------------------
		-- Button
		----------------------------------------------------------------
		function Section:AddButton(c, cb)
			c, cb = norm(c, cb)
			local frame = new("Frame", { Name = "Button", Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = sec })
			local bg = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, 0),
				BorderSizePixel = 0, Parent = frame }, { corner(4) })
			accent(bg, "BackgroundColor3")
			local lbl = text(bg, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -10, 1, 0), Font = Enum.Font.GothamBlack,
				Text = tostring(c.Title or "Button"), TextTruncate = Enum.TextTruncate.AtEnd })
			local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = bg })
			local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
				BorderSizePixel = 0, ZIndex = 2, Parent = bg }, { corner(4) })
			b.MouseButton1Click:Connect(function()
				flash.BackgroundTransparency = 0.7
				tween(flash, { BackgroundTransparency = 1 }, T.T1)
				task.spawn(cb)
			end)
			return { Fire = function() task.spawn(cb) end, SetTitle = function(_, s) lbl.Text = tostring(s) end, Type = "Button" }
		end

		----------------------------------------------------------------
		-- Label
		----------------------------------------------------------------
		function Section:AddLabel(c)
			if type(c) ~= "table" then c = { Title = tostring(c) } end
			local frame = new("Frame", { Name = "Label", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
				LayoutOrder = nextOrder(), Parent = sec }, { new("UIPadding", { PaddingBottom = UDim.new(0, 6) }) })
			local bg = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1, -10, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.Bg1, BorderSizePixel = 0, Parent = frame }, { corner(4) })
			local lbl = text(bg, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				Font = Enum.Font.GothamBlack, Text = tostring(c.Title or ""), TextWrapped = true })
			new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), Parent = lbl })
			return {
				SetText = function(_, s) lbl.Text = tostring(s) end,
				SetColor = function(_, col) lbl.TextColor3 = col end,
				Type = "Label",
			}
		end

		----------------------------------------------------------------
		-- Textbox (title + input, optional icon)
		----------------------------------------------------------------
		function Section:AddTextbox(c, cb)
			c, cb = norm(c, cb)
			local Box = { Title = c.Title, Value = tostring(c.Default or "") }
			local _, bg1 = makeRow(60, "Textbox")
			text(bg1, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -10, 0.5, 0), Font = Enum.Font.GothamBlack, Text = tostring(c.Title or "Textbox"),
				TextTruncate = Enum.TextTruncate.AtEnd })
			local bg2 = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0, 40), Size = UDim2.new(1, -10, 0, 25),
				BackgroundColor3 = T.Bg2, BorderSizePixel = 0, ClipsDescendants = true, Parent = bg1 }, { corner(4) })
			local input = new("TextBox", { Position = UDim2.fromOffset(5, 0), Size = UDim2.new(1, c.Icon and -30 or -10, 1, 0), BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold, Text = Box.Value, PlaceholderText = c.Placeholder or "", PlaceholderColor3 = T.Placeholder,
				TextSize = 14, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = bg2 })
			if c.Icon then
				new("ImageLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 0), Size = UDim2.fromOffset(15, 15),
					BackgroundTransparency = 1, Image = c.Icon, ImageColor3 = T.Icon, Parent = bg2 })
			end
			local hl = new("Frame", { Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = bg2 })
			accent(hl, "BackgroundColor3")
			input.Focused:Connect(function() tween(hl, { BackgroundTransparency = 0 }) end)
			input.FocusLost:Connect(function()
				tween(hl, { BackgroundTransparency = 1 })
				Box.Value = input.Text
				pushFlag(Box, input.Text)
				task.spawn(cb, input.Text)
			end)
			function Box:Set(val, silent, animate)
				val = tostring(val == nil and "" or val)
				self.Value = val
				pushFlag(self, val)
				if animate then
					task.spawn(function()
						for i = 1, #val do
							input.Text = string.sub(val, 1, i)
							task.wait(0.02)
						end
					end)
				else
					input.Text = val
				end
				if not silent then task.spawn(cb, val) end
			end
			function Box:Get() return input.Text end
			return register(fprefix, c, Box, "Textbox", Box.Value)
		end

		----------------------------------------------------------------
		-- Text indicator (read-only value display)
		----------------------------------------------------------------
		function Section:AddTextIndicator(c)
			c = norm(c)
			local Ind = { Title = c.Title, Value = tostring(c.Default or "") }
			local _, bg = makeRow(35, "TextIndicator")
			local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 0, 25),
				BackgroundColor3 = T.Bg2, BorderSizePixel = 0, ClipsDescendants = true, Parent = bg }, { corner(4) })
			local lbl = text(box, { Position = UDim2.fromOffset(5, 0), Size = UDim2.new(1, c.Icon and -30 or -10, 1, 0), Text = Ind.Value,
				TextTruncate = Enum.TextTruncate.AtEnd })
			if c.Icon then
				new("ImageLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 0), Size = UDim2.fromOffset(15, 15),
					BackgroundTransparency = 1, Image = c.Icon, ImageColor3 = T.Icon, Parent = box })
			end
			function Ind:Set(val, animate)
				val = tostring(val == nil and "" or val)
				self.Value = val
				pushFlag(self, val)
				if animate == true then
					task.spawn(function()
						for i = 1, #val do
							lbl.Text = string.sub(val, 1, i)
							task.wait(0.02)
						end
					end)
				else
					lbl.Text = val
				end
			end
			function Ind:Get() return self.Value end
			return register(fprefix, c, Ind, "TextIndicator", Ind.Value)
		end

		----------------------------------------------------------------
		-- Slider
		----------------------------------------------------------------
		function Section:AddSlider(c, cb)
			c, cb = norm(c, cb)
			local min, max = c.Min or 0, c.Max or 100
			local decimals = c.Decimals or (c.Precise and 1) or 0
			local mult = 10 ^ decimals
			local pre, suf = c.Prefix or "", c.Suffix or ""
			local function round(x) return math.floor(x * mult + 0.5) / mult end
			local function fmt(x)
				if decimals > 0 then return string.format("%." .. decimals .. "f", x) end
				return tostring(math.floor(x + 0.5))
			end
			local Slider = { Title = c.Title, Min = min, Max = max, Value = math.clamp(round(c.Default or min), min, max) }

			local _, bg = makeRow(50, "Slider")
			text(bg, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -90, 0, 25), Font = Enum.Font.GothamBlack, Text = tostring(c.Title or "Slider"),
				TextTruncate = Enum.TextTruncate.AtEnd })
			local vbox = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 3), Size = UDim2.fromOffset(70, 20),
				BackgroundColor3 = T.Bg2, BorderSizePixel = 0, Parent = bg }, { corner(4) })
			local vinput = new("TextBox", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "",
				TextSize = 14, TextColor3 = T.Text, ClearTextOnFocus = false, Parent = vbox })
			local track = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.new(1, -20, 0, 6),
				BackgroundColor3 = T.SliderLine, BorderSizePixel = 0, Parent = bg }, { corner(3) })
			local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = track }, { corner(3) })
			accent(fill, "BackgroundColor3")
			local hit = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1, Text = "", Parent = track })

			local function render(animate)
				local a = (max == min) and 0 or (Slider.Value - min) / (max - min)
				if animate then tween(fill, { Size = UDim2.fromScale(a, 1) }, T.T3) else fill.Size = UDim2.fromScale(a, 1) end
				vinput.Text = pre .. fmt(Slider.Value) .. suf
			end
			function Slider:Set(val, silent, noAnimate)
				val = math.clamp(round(tonumber(val) or self.Value), min, max)
				local changed = val ~= self.Value
				self.Value = val
				render(not noAnimate)
				pushFlag(self, val)
				if changed and not silent then task.spawn(cb, val) end
			end
			function Slider:Get() return self.Value end

			local function fromMouse()
				local x = UIS:GetMouseLocation().X
				local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
				Slider:Set(min + (max - min) * a, false, true)
			end
			local dragging = false
			hit.InputBegan:Connect(function(i)
				if isClick(i) then dragging = true fromMouse() end
			end)
			wconnect(UIS.InputChanged, function(i)
				if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromMouse() end
			end)
			wconnect(UIS.InputEnded, function(i) if isClick(i) then dragging = false end end)
			vinput.FocusLost:Connect(function()
				local n = tonumber(vinput.Text:match("-?%d+%.?%d*"))
				if n then Slider:Set(n) else render() end
			end)

			render()
			return register(fprefix, c, Slider, "Slider", Slider.Value)
		end

		----------------------------------------------------------------
		-- Dropdown (single or Multi)
		----------------------------------------------------------------
		function Section:AddDropdown(c, cb)
			c, cb = norm(c, cb)
			local options = c.Options or {}
			local multi = c.Multi and true or false
			local open = false
			local Dropdown = { Title = c.Title, Multi = multi }

			-- multi keeps a set { [name] = true }, single keeps the chosen name
			local function toSet(val)
				local set = {}
				if type(val) == "table" then
					for k, x in pairs(val) do
						if type(k) == "number" then set[x] = true elseif x then set[k] = true end
					end
				elseif val ~= nil then
					set[val] = true
				end
				return set
			end
			local cur
			if multi then cur = toSet(c.Default) else cur = c.Default or options[1] end
			local function selectedList()
				local out = {}
				for _, name in ipairs(options) do
					if cur[name] then table.insert(out, name) end
				end
				return out
			end
			local function value() if multi then return selectedList() end return cur end
			local function isSelected(name) if multi then return cur[name] == true end return name == cur end

			local frame = new("Frame", { Name = "Dropdown", Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = sec })
			local bg1 = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, 0),
				BackgroundColor3 = T.Bg1, BorderSizePixel = 0, ClipsDescendants = true, Parent = frame }, { corner(4) })
			local head = new("Frame", { Size = UDim2.new(1, 0, 0, 25), BackgroundColor3 = T.Bg2, BorderSizePixel = 0, ZIndex = 2, Parent = bg1 }, { corner(4) })
			local label = text(head, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -40, 1, 0), Font = Enum.Font.GothamBlack,
				TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 })
			local arrow = new("ImageLabel", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(15, 15),
				BackgroundTransparency = 1, Image = A.Arrow, ImageColor3 = T.Icon, ZIndex = 2, Parent = head })
			local dbtn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 3, Parent = head })
			local holder = new("Frame", { Position = UDim2.fromOffset(0, 25), Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, ClipsDescendants = true, Parent = bg1 })
			local scroll = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
				ScrollBarThickness = 5, CanvasSize = UDim2.new(), Parent = holder })
			local scont = new("Frame", { Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -15, 1, -5), BackgroundTransparency = 1, Parent = scroll })
			local lay = new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = scont })
			lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				scroll.CanvasSize = UDim2.fromOffset(0, lay.AbsoluteContentSize.Y + 10)
			end)

			local items = {}
			local function refresh()
				local shown
				if multi then
					local names = {}
					for _, n in ipairs(selectedList()) do table.insert(names, tostring(n)) end
					shown = #names == 0 and "None" or table.concat(names, ", ")
				else
					shown = cur == nil and "None" or tostring(cur)
				end
				label.Text = tostring(c.Title or "Dropdown") .. ": " .. shown
				for name, it in pairs(items) do tween(it.bar, { BackgroundTransparency = isSelected(name) and 0 or 1 }) end
				Dropdown.Value = value()
			end
			local function commit(fire)
				refresh()
				pushFlag(Dropdown, Dropdown.Value)
				if fire then task.spawn(cb, Dropdown.Value) end
			end
			local function rebuild()
				for _, ch in ipairs(scont:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
				items = {}
				for i, name in ipairs(options) do
					local it = new("Frame", { Name = tostring(name), Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, LayoutOrder = i, Parent = scont })
					local ln = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 14, 1, 0),
						BackgroundTransparency = 1, Parent = it })
					local b = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, -10),
						BackgroundTransparency = 1, BorderSizePixel = 0, Parent = ln }, { corner(4) })
					accent(b, "BackgroundColor3")
					text(it, { Position = UDim2.fromOffset(15, 0), Size = UDim2.new(1, -15, 1, 0), Text = tostring(name), TextTruncate = Enum.TextTruncate.AtEnd })
					local click = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = it })
					items[name] = { bar = b }
					click.MouseButton1Click:Connect(function()
						if multi then
							if cur[name] then cur[name] = nil else cur[name] = true end
						else
							cur = name
						end
						commit(true)
					end)
				end
				refresh()
			end
			rebuild()

			dbtn.MouseButton1Click:Connect(function()
				open = not open
				local listH = math.min(#options * 25 + 10, 170)
				tween(holder, { Size = UDim2.new(1, 0, 0, open and listH or 0) }, T.T2)
				tween(frame, { Size = UDim2.new(1, 0, 0, open and (25 + listH) or 25) }, T.T2)
				tween(arrow, { Rotation = open and 90 or 0 }, T.T2)
			end)

			function Dropdown:Set(val, silent)
				if multi then cur = toSet(val) else cur = val end
				commit(not silent)
			end
			function Dropdown:Get() return value() end
			function Dropdown:Refresh(newOptions, keep)
				options = newOptions or {}
				if multi then
					if not keep then
						cur = {}
					else
						for name in pairs(cur) do
							if not table.find(options, name) then cur[name] = nil end
						end
					end
				elseif not keep or not table.find(options, cur) then
					cur = options[1]
				end
				rebuild()
				pushFlag(Dropdown, Dropdown.Value)
			end
			refresh()
			return register(fprefix, c, Dropdown, "Dropdown", Dropdown.Value)
		end

		----------------------------------------------------------------
		-- Bind (keybind). ToggleUI = true makes it the window's toggle key.
		----------------------------------------------------------------
		function Section:AddBind(c, cb)
			c, cb = norm(c, cb)
			local key = toKey(c.Default)
			local listening = false
			local Bind = { Title = c.Title, Value = key }
			if c.ToggleUI and key then setToggleKey(key) end

			local _, bg = makeRow(35, "Bind")
			text(bg, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -100, 1, 0), Font = Enum.Font.GothamBlack, Text = tostring(c.Title or "Bind"),
				TextTruncate = Enum.TextTruncate.AtEnd })
			local kb = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 0), Size = UDim2.fromOffset(80, 25),
				BackgroundColor3 = T.Bg2, BorderSizePixel = 0, Parent = bg }, { corner(4) })
			local btn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = keyName(key),
				TextSize = 14, TextColor3 = T.Text, Parent = kb })

			function Bind:Set(k)
				local nk = toKey(k)
				if k == nil or k == "None" or nk then key = nk end
				self.Value = key
				btn.Text = keyName(key)
				pushFlag(self, key and key.Name or "None")
				if c.ToggleUI and key then setToggleKey(key) end
			end
			function Bind:Get() return key end

			btn.MouseButton1Click:Connect(function()
				if listening then return end
				listening = true
				rebinding = true
				rebindAt = os.clock()
				btn.Text = "..."
				task.wait(0.1)
				local conn
				conn = UIS.InputBegan:Connect(function(i)
					local picked
					if i.UserInputType == Enum.UserInputType.Keyboard then
						if i.KeyCode == Enum.KeyCode.Escape then picked = false
						elseif i.KeyCode == Enum.KeyCode.Backspace then picked = "clear"
						else picked = i.KeyCode end
					elseif i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.MouseButton2
						or i.UserInputType == Enum.UserInputType.MouseButton3 then
						picked = i.UserInputType
					end
					if picked == nil then return end
					conn:Disconnect()
					task.defer(function() listening = false rebinding = false end)
					if picked == "clear" then Bind:Set(nil) elseif picked ~= false then Bind:Set(picked) else btn.Text = keyName(key) end
				end)
			end)

			wconnect(UIS.InputBegan, function(i, gp)
				if listening or gp or not key or c.ToggleUI then return end
				if i.KeyCode == key or i.UserInputType == key then task.spawn(cb, key) end
			end)

			return register(fprefix, c, Bind, "Bind", key and key.Name or "None")
		end

		----------------------------------------------------------------
		-- Colorpicker (own row)
		----------------------------------------------------------------
		function Section:AddColorpicker(c, cb)
			c, cb = norm(c, cb)
			local startColor = typeof(c.Default) == "Color3" and c.Default or Color3.new(1, 1, 1)
			local _, bg = makeRow(30, "Colorpicker")
			text(bg, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -50, 1, 0), Font = Enum.Font.GothamBlack,
				Text = tostring(c.Title or "Colorpicker"), TextTruncate = Enum.TextTruncate.AtEnd })
			local sq = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(25, 18),
				BackgroundColor3 = startColor, BorderSizePixel = 0, Parent = bg }, { corner(4), stroke(T.Border, 1.5) })
			local CP = buildPicker(sq, startColor, cb)
			CP.Title = c.Title
			return register(fprefix, c, CP, "Colorpicker", CP.Value)
		end

		----------------------------------------------------------------
		-- Config manager (save / load / delete / auto-load, one per script)
		----------------------------------------------------------------
		function Section:AddConfigManager()
			if Library._ConfigManagerMade then
				warn("[Library] Config manager already exists - only one is allowed.")
				return
			end
			Library._ConfigManagerMade = true
			local CM = { Selected = nil }

			local holder = new("Frame", { Name = "ConfigManager", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
				LayoutOrder = nextOrder(), Parent = sec },
				{ new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }),
				  new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }) })

			text(holder, { Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.GothamBlack, Text = "Config Manager", LayoutOrder = 0 })

			local selFrame = new("Frame", { Size = UDim2.new(1, 0, 0, 25), BackgroundColor3 = T.Bg1, BorderSizePixel = 0, LayoutOrder = 1, Parent = holder }, { corner(4) })
			local selLabel = text(selFrame, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -15, 1, 0), Text = "selected: none",
				TextTruncate = Enum.TextTruncate.AtEnd })

			local list = new("ScrollingFrame", { Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = T.Bg1, BorderSizePixel = 0, ScrollBarThickness = 3,
				ScrollBarImageColor3 = T.SliderLine, Active = true, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
				Parent = holder },
				{ corner(4), new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
				  new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 4) }) })

			local nameWrap = new("Frame", { Size = UDim2.new(1, 0, 0, 25), BackgroundColor3 = T.Bg2, BorderSizePixel = 0, LayoutOrder = 3, Parent = holder }, { corner(4) })
			local nameBox = new("TextBox", { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
				Text = "", PlaceholderText = "Config name...", PlaceholderColor3 = T.Placeholder, TextSize = 14, TextColor3 = T.Text,
				TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = nameWrap })

			local rowOrder = 3
			local function makeButtons(a, aFn, b, bFn)
				rowOrder = rowOrder + 1
				local row = new("Frame", { Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1, LayoutOrder = rowOrder, Parent = holder })
				local function mk(label, fn, xs, xo)
					local btn = new("TextButton", { Position = UDim2.new(xs, xo, 0, 0), Size = UDim2.new(0.5, -3, 1, 0), BackgroundColor3 = T.Bg2, BorderSizePixel = 0,
						AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = label, TextSize = 14, TextColor3 = T.Text, Parent = row }, { corner(4) })
					btn.MouseEnter:Connect(function() tween(btn, { TextColor3 = T.Accent }, T.T3) end)
					btn.MouseLeave:Connect(function() tween(btn, { TextColor3 = T.Text }, T.T3) end)
					btn.MouseButton1Click:Connect(function() task.spawn(fn) end)
				end
				mk(a, aFn, 0, 0)
				mk(b, bFn, 0.5, 3)
			end

			local function configPath(name) return Library.Directory .. Library.Folders.Configs .. "/" .. name .. ".json" end
			local function selectConfig(name)
				CM.Selected = name
				selLabel.Text = "selected: " .. (name or "none")
			end

			function CM:Refresh()
				for _, ch in ipairs(list:GetChildren()) do
					if ch:IsA("TextButton") then ch:Destroy() end
				end
				ensureFolders()
				local names = Library:GetConfigsList()
				table.sort(names)
				for idx, name in ipairs(names) do
					local item = new("TextButton", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, AutoButtonColor = false, LayoutOrder = idx,
						Font = (name == CM.Selected) and Enum.Font.GothamBlack or Enum.Font.GothamBold, Text = name, TextSize = 14,
						TextColor3 = (name == CM.Selected) and T.Accent or T.Text, TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd, Parent = list })
					item.MouseButton1Click:Connect(function()
						selectConfig(name)
						CM:Refresh()
					end)
				end
			end

			makeButtons("Refresh", function() CM:Refresh() end, "Set Auto-Load", function()
				if not CM.Selected then return Library:Notify("Config", "Select a config first") end
				pcall(writefile, Library.Directory .. "/AutoLoad.json", CM.Selected)
				Library:Notify("Config", "Auto-Load set to " .. CM.Selected)
			end)
			makeButtons("Delete", function()
				if not CM.Selected then return end
				pcall(function()
					local p = configPath(CM.Selected)
					if isfile(p) then delfile(p) end
				end)
				selectConfig(nil)
				CM:Refresh()
			end, "New", function()
				local name = nameBox.Text
				if not name or #name == 0 then name = "config_" .. tostring(os.time()) end
				selectConfig(name)
				CM:Refresh()
			end)
			makeButtons("Save", function()
				local name = CM.Selected or nameBox.Text
				if not name or #name == 0 then return Library:Notify("Config", "Enter a name first") end
				local encoded = Library:GetConfig()
				if not encoded then return Library:Notify("Config", "Failed to encode") end
				ensureFolders()
				local ok, err = pcall(writefile, configPath(name), encoded)
				if not ok then return Library:Notify("Config", "Save failed: " .. tostring(err)) end
				selectConfig(name)
				CM:Refresh()
				Library:Notify("Config", "Saved " .. name)
			end, "Load", function()
				if not CM.Selected then return Library:Notify("Config", "Select a config first") end
				local ok, data = pcall(function()
					local p = configPath(CM.Selected)
					if isfile(p) then return readfile(p) end
				end)
				if ok and data then
					Library:LoadConfig(data)
					Library:Notify("Config", "Loaded " .. CM.Selected)
				else
					Library:Notify("Config", "Could not read " .. CM.Selected)
				end
			end)

			CM:Refresh()
			return CM
		end

		-- old-API names + short aliases
		Section.AddBox, Section.CreateBox = Section.AddTextbox, Section.AddTextbox
		Section.AddKeybind = Section.AddBind
		for _, n in ipairs({ "Toggle", "Button", "Label", "Textbox", "TextIndicator", "Slider", "Dropdown", "Bind", "Colorpicker", "ConfigManager" }) do
			Section["Create" .. n] = Section["Add" .. n]
		end
	end

	----------------------------------------------------------------
	-- Tabs -> sub tabs -> sections
	----------------------------------------------------------------
	function Window:AddTab(Title)
		Title = tostring(Title or "Tab")
		local Tab = { Title = Title, Subs = {}, SelectedSub = nil }
		
		local row = new("Frame", { Name = Title .. "_Tab", Size = UDim2.new(1, -10, 0, 25), BackgroundTransparency = 1, LayoutOrder = #Window.Tabs + 1, Parent = tabScroll })
		local inner = new("Frame", { Position = UDim2.fromOffset(5, 0), Size = UDim2.new(1, -5, 1, 0), BackgroundTransparency = 1, Parent = row })
		local line = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 14, 1, 0),
			BackgroundTransparency = 1, Parent = inner })
		local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, -10, 0, 0),
			BorderSizePixel = 0, Parent = line }, { corner(2) })
		accent(bar, "BackgroundColor3")
		text(inner, { Position = UDim2.fromOffset(15, 0), Size = UDim2.new(1, -15, 1, 0), Text = Title })
		local tabBtn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = inner })

		local content = new("Frame", { Name = Title .. "_Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = card })
		local subBar = new("Frame", { Name = "SubTabs", Position = UDim2.fromOffset(5, 0), Size = UDim2.new(1, -35, 0, 30), BackgroundTransparency = 1, Parent = content },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
			  new("UIPadding", { PaddingLeft = UDim.new(0, 5) }) })
		local pages = new("Frame", { Name = "Pages", Position = UDim2.fromOffset(5, 32), Size = UDim2.new(1, -10, 1, -37), BackgroundTransparency = 1,
			ClipsDescendants = true, Parent = content })

		function Tab:_Deselect()
			content.Visible = false
			tween(bar, { Size = UDim2.new(1, -10, 0, 0), Position = UDim2.fromScale(0.5, 1), AnchorPoint = Vector2.new(0.5, 1) })
		end
		function Tab:Select()
			local prev = Window.SelectedTab
			if prev and prev ~= Tab then prev:_Deselect() end
			Window.SelectedTab = Tab
			content.Visible = true
			tween(bar, { Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
			applySearch()
		end
		tabBtn.MouseButton1Click:Connect(function() Tab:Select() end)

		function Tab:AddSubTab(SubTitle)
			SubTitle = tostring(SubTitle or "Sub Tab")
			local Sub = { Title = SubTitle, Sections = {}, Tab = Tab, Counts = { Left = 0, Right = 0 } }

			local sbtn = new("TextButton", { Name = SubTitle, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
				AutoButtonColor = false, Font = Enum.Font.GothamBold, Text = SubTitle, TextSize = 14, TextColor3 = T.Desc, LayoutOrder = #Tab.Subs + 1, Parent = subBar })
			local ul = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(0, 0, 0, 2), BorderSizePixel = 0,
				Parent = sbtn }, { corner(1) })
			accent(ul, "BackgroundColor3")

			local page = new("Frame", { Name = SubTitle .. "_Page", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = pages })
			-- one full-width column: sections stack under each other like the original Feral
			local function column()
				return new("ScrollingFrame", { Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
					BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = T.SliderLine, Active = true, CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = page },
					{ new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }),
					  new("UIPadding", { PaddingRight = UDim.new(0, 5) }) })
			end
			local mainColumn = column()
			local columns = { Left = mainColumn, Right = mainColumn }   -- "Left"/"Right" still accepted, both go in the same column

			function Sub:_Deselect()
				page.Visible = false
				tween(ul, { Size = UDim2.new(0, 0, 0, 2) })
				tween(sbtn, { TextColor3 = T.Desc })
			end
			function Sub:Select()
				local prev = Tab.SelectedSub
				if prev and prev ~= Sub then prev:_Deselect() end
				Tab.SelectedSub = Sub
				page.Visible = true
				tween(ul, { Size = UDim2.new(1, 0, 0, 2) })
				tween(sbtn, { TextColor3 = T.Text })
				applySearch()
			end
			sbtn.MouseButton1Click:Connect(function() Sub:Select() end)

			-- Side: "Left" / "Right"; nil = whichever column has fewer sections
			function Sub:_AddSection(secName, Side)
				secName = tostring(secName or "Section")
				if Side == nil then
					Side = (Sub.Counts.Left <= Sub.Counts.Right) and "Left" or "Right"
				end
				Side = (tostring(Side):lower() == "right") and "Right" or "Left"
				Sub.Counts[Side] = Sub.Counts[Side] + 1

				local sec = new("Frame", { Name = secName .. "_Section", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = T.Bg3, BorderSizePixel = 0, LayoutOrder = Sub.Counts.Left + Sub.Counts.Right, Parent = columns[Side] },
					{ corner(4), new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }),
					  new("UIPadding", { PaddingBottom = UDim.new(0, 5) }) })

				local topsec = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 0, Parent = sec })
				local stitle = text(topsec, { Size = UDim2.fromScale(1, 1), Text = secName, TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd })
				accent(stitle, "TextColor3")
				local uline = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -10, 0, 2),
					BorderSizePixel = 0, Parent = topsec },
					{ new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0),
						NumberSequenceKeypoint.new(0.51, 0.02), NumberSequenceKeypoint.new(1, 1) }) }) })
				accent(uline, "BackgroundColor3")

				table.insert(Sub.Sections, { Title = secName, Frame = sec })

				local Section = { Title = secName, Instance = sec, Frame = sec }
				buildControls(Section, sec, Tab.Title .. "/" .. Sub.Title .. "/" .. secName .. "/")
				return Section
			end
			function Sub:AddSection(secName, Side) return Sub:_AddSection(secName, Side or "Left") end
			function Sub:CreateSection(secName, Side) return Sub:_AddSection(secName, Side) end

			if #Tab.Subs == 0 then Sub:Select() end
			table.insert(Tab.Subs, Sub)
			return Sub
		end
		Tab.CreateSubTab = Tab.AddSubTab

		if #Window.Tabs == 0 then Tab:Select() end
		table.insert(Window.Tabs, Tab)
		return Tab
	end

	-- old API: one tab + one sub tab, sections spread over both columns
	function Window:CreatePage(name, title, logo)
		local Tab = self:AddTab(name, logo)
		local Sub = Tab:AddSubTab(title or name)
		local Page = { Tab = Tab, SubTab = Sub }
		function Page:CreateSection(secName, Side) return Sub:_AddSection(secName, Side) end
		function Page:AddSection(secName, Side) return Sub:_AddSection(secName, Side) end
		function Page:AddSubTab(t) return Tab:AddSubTab(t) end
		function Page:Select() Tab:Select() end
		return Page
	end

	table.insert(Library.Windows, Window)
	return Window
end
Library.CreateMain = Library.Window

if getgenv then getgenv().Library = Library end
return Library
