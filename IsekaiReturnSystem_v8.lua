--[[
	ISEKAI / RETURN SYSTEM  v8
	Navigation • Recovery • Session Control

	Jenis   : LocalScript (client). Jalankan di executor ATAU taruh di StarterPlayerScripts.
	Fitur   : Save multi-slot (CFrame), Return, Delete (konfirmasi), persistence file JSON,
	          Auto Return (memantau posisi: karakter bergeser sedikit saja -> otomatis kembali),
	          Anti-AFK (tekan keybind berulang tiap interval 1-19 menit),
	          FIND: cari item yang bisa diambil (Coin / Gold / Key / Gem / Chest / Orb), ESP, filter jenis, Loop Find,
	          interaksi/keybind per kategori, lompat, berenang, teleport berjarak, rute berurutan (terdekat dulu),
	          UI glass gelap, intro 4 detik, toast notifikasi, minimize/close, Advanced Autoexecute + Anti-Stuck, cleanup aman.

	Logika berjalan (Return & Find):
	  - Jika karakter sedang duduk, otomatis meloncat keluar dari kursi dulu.
	  - Rute memakai PathfindingService; jika terhalang, rute dihitung ulang dengan parameter lain,
	    mencoba menyamping/memutar lewat arah yang terbuka, lalu mencoba rute memutar (detour).
	  - Return: teleport HANYA cadangan setelah batas waktu berjalan (120 detik) habis.

	UI (v8): empat tab -> Return, Find, AFK, Advanced. Advanced menambahkan Autoexecute saat teleport/rejoin dan Anti-Stuck global.

	Logika Find (v8):
	  1. Scan    : memindai Workspace; hasil dipisah per kategori, JENIS objek (Part / Model / Tool) dan
	               PEMICU ambil (Prompt / Click / Touch / Tanpa pemicu), lengkap dengan jumlahnya di daftar hasil.
	  2. Item    : secara default hanya objek yang BISA DIAMBIL (punya ProximityPrompt, ClickDetector,
	               TouchInterest atau Tool). Objek dekorasi bernama "Gold" tidak ikut. Chip "Tanpa pemicu"
	               menyertakan objek yang hanya cocok nama.
	  3. ESP     : toggle ON/OFF menandai posisi item (nama + jarak) dan memindai ulang berkala.
	  4. Filter  : "Hindari Air" / "Hindari Bahaya" membuang target di air / dekat lava, kill brick, jurang.
	  5. Walk    : berjalan berurutan dari target terdekat; loncat otomatis (halangan rendah, Coin/Gold tinggi).
	  6. Teleport: TIDAK langsung ke item. Karakter dipindah ke titik beberapa stud dari item (jarak bisa diatur),
	               lalu berjalan / loncat / berenang mendekat dan bolak-balik melewati item sampai terambil.
	  7. Air     : bila item di air, karakter berenang 3D ke arah item (naik/turun), bukan hanyut mengapung.
	  8. Stuck   : tersangkut / tidak terjangkau -> teleport berjarak lebih dekat (maks 2x). Teleport langsung
	               ke item hanya cadangan paling akhir.
	  Menekan tombol gerak (WASD/panah) atau tombol Stop membatalkan Find.

	Persistence: memakai writefile/readfile/isfile/makefolder milik executor bila tersedia. Autoexecute membutuhkan URL raw script dan queue_on_teleport dari executor bila ingin berlanjut lintas teleport.
	Semua pengaturan (slot, slot terpilih, Auto Return, kecepatan, jeda, jarak deteksi,
	Anti-AFK on/off, keybind, interval, pengaturan Find) disimpan ke file dan dipulihkan saat script
	dijalankan lagi. Tanpa API itu, data hanya hidup selama sesi (script tidak berpura-pura menyimpan).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
if not player then
	return
end

local globalEnv = (type(getgenv) == "function" and getgenv()) or _G
local INSTANCE_KEY = "__IsekaiReturnSystem"

-- Hanya satu instance: tutup instance lama (jika ada) sebelum mulai.
local previous = globalEnv[INSTANCE_KEY]
if type(previous) == "table" and type(previous.Cleanup) == "function" then
	pcall(previous.Cleanup)
end

--------------------------------------------------------------------------------
-- CONFIG & THEME
--------------------------------------------------------------------------------

local CONFIG = {
	Title = "ISEKAI / RETURN SYSTEM",
	Subtitle = "Navigation • Recovery • Session Control",
	IntroTitle = "ISID Return System",
	Credit = "Developed by Denis Cepaka & Claude",
	MaxSlots = 20,
	MaxNameLength = 24,
	DataFolder = "IsekaiReturnSystem",
	DataFile = "IsekaiReturnSystem/positions.json",
	DataVersion = 4,
	AutoSaveInterval = 15, -- detik; simpan ulang berkala bila ada perubahan
	IntroDuration = 4,
	IntroFadeOut = 0.6,
	AfkMinMinutes = 1,
	AfkMaxMinutes = 19,
	DefaultAfkMinutes = 15,
	DefaultKey = "Space", -- tombol yang DITEKAN oleh Anti-AFK (bukan hotkey toggle)
	ToastDuration = 2.8,
	MaxToasts = 3,
	ToastHeight = 54,
	DuplicateDistance = 0.75,
	MaxLift = 8,
	LiftStep = 0.5,
	WalkMaxTime = 120, -- batas waktu berjalan sebelum teleport cadangan dipertimbangkan
	WalkHardMax = 150, -- batas mutlak (jika di 120 dtk masih dekat & terus bergerak, diberi tambahan waktu)
	FarDistance = 20, -- "benar-benar jauh" saat batas waktu habis (stud)
	StuckConfirm = 3, -- detik tidak bergeser = dianggap nyangkut saat batas waktu habis
	ArriveDistance = 3,
	SpeedMin = 30,
	SpeedMax = 130,
	SpeedDefault = 100,
	DelayMax = 30,
	DelayDefault = 3,
	TriggerMin = 1.5, -- jarak geser (stud) yang memicu Auto Return
	TriggerMax = 20,
	TriggerDefault = 2.5,
	WatchInterval = 0.25,

	-- FIND
	FindMaxResults = 400, -- batas jumlah target hasil scan
	FindMaxSize = 40, -- objek lebih besar dari ini (stud) dianggap bagian peta, bukan item
	FindMaxTransparency = 0.98, -- objek (hampir) transparan penuh dianggap tidak ada / sudah diambil
	FindCustomMaxLength = 80, -- panjang maksimal teks kata kunci manual
	FindMaxKeywords = 8,
	FindArriveDistance = 3.5, -- jarak datar untuk mulai pendekatan akhir (stud)
	FindFinalTime = 3, -- batas waktu pendekatan akhir sebelum teleport cadangan
	FindStuckTime = 3, -- detik tidak bergeser -> LANGSUNG teleport ke objek
	FindNoProgressTime = 10, -- detik bergerak tapi tidak mendekat -> teleport
	FindTargetTimeout = 15, -- batas maksimal untuk memastikan target berhasil diambil
	FindCollectTimeout = 15, -- tunggu target hilang/terambil sebelum dilewati
	FindFailedCoinRejoinLimit = 3, -- tiga Coin gagal diambil (di-skip) berturut-turut memicu rejoin
	FindTeleportCollectDelay = 3, -- waktu tunggu setelah teleport agar item sempat terambil
	FindLoopDelay = 2.5, -- jeda antar-scan saat Loop Find aktif
	FindHighItemJumpHeight = 2.5, -- Coin/Gold di atas karakter: mulai coba melompat
	FindHighItemJumpDistance = 18, -- jangan melompat ke target tinggi yang masih terlalu jauh
	HazardMargin = 3, -- jarak aman rute dari objek bahaya (stud)
	HazardTargetMargin = 5, -- target lebih dekat dari ini ke objek bahaya dilewati (stud)
	FindMaxRaw = 600, -- batas hasil mentah scan (sebelum filter jenis / pemicu)
	FindStandoffMin = 5, -- jarak teleport minimum dari item (stud)
	FindStandoffMax = 30,
	FindStandoffDefault = 14,
	FindStandoffRetries = 2, -- berapa kali teleport berjarak ulang (makin dekat) sebelum cadangan terakhir
	FindRetryTimeout = 8, -- batas waktu percobaan ulang setelah teleport berjarak
	FindSweepTime = 4, -- detik bolak-balik melewati item bila sudah dekat tapi belum terambil
	EspRescanInterval = 6, -- jeda scan ulang saat ESP aktif (detik)
	AntiStuckPollInterval = 0.35, -- interval pemantauan karakter global
	AntiStuckMoveTimeout = 4, -- input gerak tanpa perpindahan selama ini memicu recovery
	AutoExecuteUrlMaxLength = 512,
	ResultListMax = 60, -- baris maksimal di daftar hasil
}

local THEME = {
	Background = Color3.fromRGB(24, 16, 40),
	BackgroundAlt = Color3.fromRGB(62, 28, 98),
	Surface = Color3.fromRGB(42, 29, 66),
	SurfaceHi = Color3.fromRGB(66, 44, 98),
	Border = Color3.fromRGB(96, 62, 138),
	Accent = Color3.fromRGB(214, 64, 206),
	AccentDark = Color3.fromRGB(122, 52, 196),
	Text = Color3.fromRGB(246, 242, 252),
	Muted = Color3.fromRGB(170, 158, 192),
	Success = Color3.fromRGB(88, 214, 141),
	Info = Color3.fromRGB(110, 168, 255),
	Warning = Color3.fromRGB(255, 190, 72),
	Error = Color3.fromRGB(255, 92, 112),
}

local KIND_COLOR = {
	success = THEME.Success,
	info = THEME.Info,
	warning = THEME.Warning,
	error = THEME.Error,
}

local KIND_GLYPH = {
	success = "✓",
	info = "i",
	warning = "!",
	error = "✕",
}

-- Kategori Find. Pencocokan memakai potongan kata pada nama objek (GoldCoin -> "gold", "coin").
local FIND_CATEGORIES = {
	{ id = "coin", label = "Coin", words = { "coin", "koin", "cash", "money" } },
	{ id = "gold", label = "Gold", words = { "gold", "emas", "ingot", "nugget" } },
	{ id = "key", label = "Key", words = { "key", "kunci" } },
	{ id = "gem", label = "Gem", words = { "gem", "diamond", "crystal", "jewel", "ruby" } },
	{ id = "chest", label = "Chest", words = { "chest", "crate", "treasure", "peti" } },
	{ id = "orb", label = "Orb", words = { "orb", "star", "token", "pickup", "collectible", "collectable" } },
}

-- Jenis objek dan cara item diambil (dipakai sebagai filter + pemisah jumlah di daftar hasil).
local FIND_KINDS = {
	{ id = "part", label = "Part" },
	{ id = "model", label = "Model" },
	{ id = "tool", label = "Tool" },
}
local FIND_TRIGGERS = {
	{ id = "prompt", label = "Prompt" },
	{ id = "click", label = "Click" },
	{ id = "touch", label = "Touch" },
	{ id = "plain", label = "Tanpa pemicu" },
}

local ESP_COLORS = {
	coin = Color3.fromRGB(255, 214, 64),
	gold = Color3.fromRGB(255, 170, 40),
	key = Color3.fromRGB(120, 210, 255),
	gem = Color3.fromRGB(120, 255, 200),
	chest = Color3.fromRGB(255, 140, 90),
	orb = Color3.fromRGB(200, 140, 255),
	custom = Color3.fromRGB(255, 255, 255),
}

local TABS = {
	{ id = "return", label = "Return" },
	{ id = "find", label = "Find" },
	{ id = "afk", label = "AFK" },
	{ id = "advanced", label = "Advanced" },
}

-- Nama objek yang dianggap berbahaya (dicocokkan sebagai kata utuh).
local HAZARD_WORDS = {
	"lava", "magma", "kill", "killbrick", "killpart", "death", "deathbrick", "damage", "hurt",
	"acid", "poison", "toxic", "spike", "laser", "electric", "shock", "hazard", "danger", "void",
}

--------------------------------------------------------------------------------
-- STATE & TRACKERS
--------------------------------------------------------------------------------

local state = {
	closed = false,
	uiReady = false,
	minimized = false,
	tab = "return",
	visToken = 0,
	slots = {}, -- semua slot (semua place); yang tampil hanya milik place ini
	selectedId = nil,
	autoReturn = false,
	walk = nil,
	walkSpeedPct = CONFIG.SpeedDefault,
	autoDelay = CONFIG.DelayDefault,
	autoTrigger = CONFIG.TriggerDefault,
	autoPauseUntil = 0,
	busy = false,
	moveToken = 0,
	capturingKey = false,
	capturingFindKey = nil,
	lastPersistError = 0,
	lastEncoded = nil,
	statusText = "Siap.",
	statusKind = "info",
	storage = { available = false, mode = "Session only" },
	advanced = {
		autoExecuteEnabled = globalEnv.__IsekaiReturnSystemAutoExecuteEnabled == true,
		scriptUrl = type(globalEnv.__IsekaiReturnSystemAutoExecuteURL) == "string" and globalEnv.__IsekaiReturnSystemAutoExecuteURL or "",
		antiStuckEnabled = true,
	},
	afk = {
		active = false,
		resume = false, -- Anti-AFK aktif saat terakhir disimpan -> dinyalakan lagi saat load
		endsAt = 0,
		minutes = CONFIG.DefaultAfkMinutes,
		keyCode = Enum.KeyCode[CONFIG.DefaultKey],
		token = 0,
		vuWarned = false,
	},
	find = {
		running = false,
		scanning = false,
		token = 0,
		categories = { coin = true, gold = true, key = true, gem = false, chest = false, orb = false },
		custom = "", -- kata kunci manual, dipisah koma
		loopEnabled = false,
		mode = "walk", -- "walk" atau "teleport" (teleport berjarak, bukan langsung ke item)
		standoff = CONFIG.FindStandoffDefault, -- jarak teleport dari item (stud)
		espEnabled = false,
		kinds = { part = true, model = true, tool = true },
		triggers = { prompt = true, click = true, touch = true, plain = false }, -- plain=false: hanya item yang bisa diambil
		raw = {}, -- hasil mentah scan (sebelum filter jenis / pemicu)
		kindCounts = { part = 0, model = 0, tool = 0 },
		trigCounts = { prompt = 0, click = 0, touch = 0, plain = 0 },
		scanned = false,
		jumpHighCoinGold = true,
		interactEnabled = { coin = false, gold = false, key = false, gem = false, chest = false, orb = false },
		interactKeys = { coin = Enum.KeyCode.E, gold = Enum.KeyCode.E, key = Enum.KeyCode.E, gem = Enum.KeyCode.E, chest = Enum.KeyCode.E, orb = Enum.KeyCode.E },
		avoidWater = false, -- default OFF: item di air didekati dengan berenang
		avoidHazard = true,
		speedPct = CONFIG.SpeedDefault,
		results = {},
		hazards = {},
		matchers = {},
		counts = {},
		truncated = false,
		total = 0,
		done = 0,
		collected = 0,
		visited = 0,
		gone = 0,
		teleports = 0,
		failedCoinSkips = 0,
		statusText = "Belum dipindai. Tekan Scan untuk menghitung target.",
	},
}

local connections = {}
local tasks = {}
local activeTweens = {}
local pendingNotices = {}
local ui = {}

local toastQueue = {}
local toastActive = 0
local toastMessages = {}
local toastCounter = 0

-- Forward declarations
local showNotification
local refreshUI
local refreshStatus
local refreshFindUI
local rebuildESP
local refreshResultList
local persistSavedData
local moveToSavedSpot
local toggleAntiAFK
local toggleAutoReturn
local startFind
local stopFind
local cleanup
local pressKey

--------------------------------------------------------------------------------
-- UTILITIES
--------------------------------------------------------------------------------

local function connect(signal, handler)
	local connection = signal:Connect(handler)
	table.insert(connections, connection)
	return connection
end

local function spawnTask(fn, ...)
	for i = #tasks, 1, -1 do
		if coroutine.status(tasks[i]) == "dead" then
			table.remove(tasks, i)
		end
	end
	local thread = task.spawn(fn, ...)
	table.insert(tasks, thread)
	return thread
end

local function tween(instance, duration, props, style, direction)
	if state.closed or not instance or not instance.Parent then
		return nil
	end
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local created = TweenService:Create(instance, info, props)
	activeTweens[created] = true
	created.Completed:Once(function()
		activeTweens[created] = nil
	end)
	created:Play()
	return created
end

local function new(className, props, children)
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(left, top, right, bottom)
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
	})
end

local function isFinite(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function resolveKeyCode(name)
	if type(name) ~= "string" then
		return nil
	end
	local ok, keyCode = pcall(function()
		return Enum.KeyCode[name]
	end)
	if ok and keyCode and keyCode ~= Enum.KeyCode.Unknown then
		return keyCode
	end
	return nil
end

-- Membersihkan teks kata kunci manual: buang karakter kontrol, rapikan spasi, batasi panjang.
local function sanitizeKeywords(raw)
	local text = tostring(raw or ""):gsub("%c", " ")
	text = text:match("^%s*(.-)%s*$")
	local length = utf8.len(text)
	if not length then
		return ""
	end
	if length > CONFIG.FindCustomMaxLength then
		local cut = utf8.offset(text, CONFIG.FindCustomMaxLength + 1)
		text = text:sub(1, (cut or (#text + 1)) - 1)
	end
	return text
end

--------------------------------------------------------------------------------
-- VALIDASI
--------------------------------------------------------------------------------

local function validateDuration(input)
	local maxMessage = string.format("Interval Anti-AFK melebihi batas maksimum (%d menit).", CONFIG.AfkMaxMinutes)
	if type(input) ~= "string" then
		return nil, "Input tidak valid."
	end
	local text = input:match("^%s*(.-)%s*$")
	if text == "" then
		return nil, "Input tidak valid: interval tidak boleh kosong."
	end
	if not text:match("^%d+$") then
		return nil, "Input tidak valid: gunakan angka bulat saja (tanpa huruf, simbol, atau desimal)."
	end
	if #text > 6 then
		return nil, maxMessage
	end
	local minutes = tonumber(text)
	if minutes > CONFIG.AfkMaxMinutes then
		return nil, maxMessage
	end
	if minutes < CONFIG.AfkMinMinutes then
		return nil, "Interval 0 menit tidak valid. Isi 1 atau lebih."
	end
	return minutes
end

local function sanitizeName(raw)
	local text = (raw or ""):gsub("%c", " ")
	text = text:match("^%s*(.-)%s*$")
	text = text:gsub("%s+", " ")
	if text == "" then
		return ""
	end
	local length = utf8.len(text)
	if not length then
		return nil, "Nama mengandung karakter tidak valid."
	end
	if length > CONFIG.MaxNameLength then
		return nil, string.format("Nama maksimal %d karakter.", CONFIG.MaxNameLength)
	end
	return text
end

local function deserializeCFrame(components)
	if type(components) ~= "table" or #components ~= 12 then
		return nil
	end
	for i = 1, 12 do
		if not isFinite(components[i]) then
			return nil
		end
	end
	local cf = CFrame.new(table.unpack(components))
	if math.abs(cf.RightVector.Magnitude - 1) > 0.01
		or math.abs(cf.UpVector.Magnitude - 1) > 0.01
		or math.abs(cf.LookVector.Magnitude - 1) > 0.01 then
		return nil
	end
	return cf
end

--------------------------------------------------------------------------------
-- STATUS
--------------------------------------------------------------------------------

local function setStatus(text, kind)
	state.statusText = text
	state.statusKind = kind or "info"
	if refreshStatus then
		refreshStatus()
	end
end

local function notify(message, kind, status)
	setStatus(status or message, kind)
	if showNotification then
		showNotification(message, kind)
	end
end

--------------------------------------------------------------------------------
-- PERSISTENCE
--------------------------------------------------------------------------------

local function detectStorage()
	-- isfile sifatnya opsional (tidak semua executor punya); readfile/writefile wajib.
	local available = type(writefile) == "function" and type(readfile) == "function"
	state.storage.available = available
	state.storage.mode = available and "Executor file" or "Session only"
end

local function parseSlot(entry)
	if type(entry) ~= "table" then
		return nil
	end
	if type(entry.id) ~= "string" or #entry.id == 0 or #entry.id > 64 then
		return nil
	end
	local name = sanitizeName(type(entry.name) == "string" and entry.name or "")
	if not name or name == "" then
		return nil
	end
	local cf = deserializeCFrame(entry.cframe)
	if not cf then
		return nil
	end
	if not isFinite(entry.placeId) then
		return nil
	end
	local camRel = nil
	if entry.camera ~= nil then
		camRel = deserializeCFrame(entry.camera)
	end
	return {
		id = entry.id,
		name = name,
		cf = cf,
		camRel = camRel,
		placeId = entry.placeId,
		gameId = isFinite(entry.gameId) and entry.gameId or 0,
		savedAt = isFinite(entry.savedAt) and entry.savedAt or os.time(),
	}
end

local function visibleSlots()
	local list = {}
	for _, slot in ipairs(state.slots) do
		if slot.placeId == game.PlaceId then
			table.insert(list, slot)
		end
	end
	return list
end

local function getSelectedSlot()
	if not state.selectedId then
		return nil
	end
	for _, slot in ipairs(state.slots) do
		if slot.id == state.selectedId and slot.placeId == game.PlaceId then
			return slot
		end
	end
	return nil
end

local function loadSavedData()
	if not state.storage.available then
		table.insert(pendingNotices, {
			"Penyimpanan file executor tidak tersedia. Posisi hanya tersimpan selama sesi.",
			"warning",
		})
		return
	end

	local okRead, raw = pcall(function()
		if type(isfile) == "function" and not isfile(CONFIG.DataFile) then
			return nil
		end
		return readfile(CONFIG.DataFile)
	end)
	if not okRead then
		if type(isfile) == "function" then
			table.insert(pendingNotices, { "Gagal membaca file data tersimpan.", "error" })
			return
		end
		raw = nil -- tanpa isfile, error baca berarti file belum ada (run pertama)
	end
	if raw == nil or type(raw) ~= "string" or raw:match("^%s*$") then
		return
	end

	local okDecode, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not okDecode or type(data) ~= "table" or type(data.slots) ~= "table" then
		pcall(writefile, CONFIG.DataFile .. ".corrupt", raw)
		table.insert(pendingNotices, {
			"File data rusak atau formatnya tidak sesuai. Salinan disimpan sebagai .corrupt.",
			"error",
		})
		return
	end

	local seen = {}
	local restored, skipped = 0, 0
	for _, entry in ipairs(data.slots) do
		local slot = parseSlot(entry)
		if slot and not seen[slot.id] then
			seen[slot.id] = true
			table.insert(state.slots, slot)
			if slot.placeId == game.PlaceId then
				restored += 1
			end
		else
			skipped += 1
		end
	end

	local settings = data.settings
	if type(settings) == "table" then
		if type(settings.autoReturn) == "boolean" then
			state.autoReturn = settings.autoReturn
		end
		if type(settings.selectedId) == "string" then
			state.selectedId = settings.selectedId
		end
		local keyCode = resolveKeyCode(settings.antiAfkKey)
		if keyCode then
			state.afk.keyCode = keyCode
		end
		if isFinite(settings.antiAfkMinutes) and settings.antiAfkMinutes % 1 == 0
			and settings.antiAfkMinutes >= CONFIG.AfkMinMinutes
			and settings.antiAfkMinutes <= CONFIG.AfkMaxMinutes then
			state.afk.minutes = settings.antiAfkMinutes
		end
		if type(settings.antiAfkEnabled) == "boolean" then
			state.afk.resume = settings.antiAfkEnabled
		end
		if isFinite(settings.walkSpeedPct) and settings.walkSpeedPct >= CONFIG.SpeedMin and settings.walkSpeedPct <= CONFIG.SpeedMax then
			state.walkSpeedPct = settings.walkSpeedPct
		end
		if isFinite(settings.autoDelay) and settings.autoDelay >= 0 and settings.autoDelay <= CONFIG.DelayMax then
			state.autoDelay = settings.autoDelay
		end
		if isFinite(settings.autoTrigger) and settings.autoTrigger >= CONFIG.TriggerMin and settings.autoTrigger <= CONFIG.TriggerMax then
			state.autoTrigger = math.floor(settings.autoTrigger / 0.5 + 0.5) * 0.5
		end

		-- Pengaturan Find
		if type(settings.findCategories) == "table" then
			for _, category in ipairs(FIND_CATEGORIES) do
				if type(settings.findCategories[category.id]) == "boolean" then
					state.find.categories[category.id] = settings.findCategories[category.id]
				end
			end
		end
		if type(settings.findCustom) == "string" then
			state.find.custom = sanitizeKeywords(settings.findCustom)
		end
		if type(settings.findAvoidWater) == "boolean" then
			state.find.avoidWater = settings.findAvoidWater
		end
		if type(settings.findAvoidHazard) == "boolean" then
			state.find.avoidHazard = settings.findAvoidHazard
		end
		if type(settings.findLoopEnabled) == "boolean" then
			state.find.loopEnabled = settings.findLoopEnabled
		end
		if settings.findMode == "walk" or settings.findMode == "teleport" then
			state.find.mode = settings.findMode
		end
		if type(settings.findJumpHighCoinGold) == "boolean" then
			state.find.jumpHighCoinGold = settings.findJumpHighCoinGold
		end
		if type(settings.findInteractEnabled) == "table" then
			for _, category in ipairs(FIND_CATEGORIES) do
				if type(settings.findInteractEnabled[category.id]) == "boolean" then
					state.find.interactEnabled[category.id] = settings.findInteractEnabled[category.id]
				end
			end
		end
		if type(settings.findInteractKeys) == "table" then
			for _, category in ipairs(FIND_CATEGORIES) do
				local keyCode = resolveKeyCode(settings.findInteractKeys[category.id])
				if keyCode then
					state.find.interactKeys[category.id] = keyCode
				end
			end
		end
		if type(settings.findKinds) == "table" then
			for _, kind in ipairs(FIND_KINDS) do
				if type(settings.findKinds[kind.id]) == "boolean" then
					state.find.kinds[kind.id] = settings.findKinds[kind.id]
				end
			end
		end
		if type(settings.findTriggers) == "table" then
			for _, trigger in ipairs(FIND_TRIGGERS) do
				if type(settings.findTriggers[trigger.id]) == "boolean" then
					state.find.triggers[trigger.id] = settings.findTriggers[trigger.id]
				end
			end
		end
		if isFinite(settings.findStandoff) and settings.findStandoff >= CONFIG.FindStandoffMin and settings.findStandoff <= CONFIG.FindStandoffMax then
			state.find.standoff = math.floor(settings.findStandoff + 0.5)
		end
		if type(settings.autoExecuteEnabled) == "boolean" then
			state.advanced.autoExecuteEnabled = settings.autoExecuteEnabled
		end
		if type(settings.autoExecuteUrl) == "string" and #settings.autoExecuteUrl <= CONFIG.AutoExecuteUrlMaxLength then
			state.advanced.scriptUrl = settings.autoExecuteUrl
		end
		if type(settings.antiStuckEnabled) == "boolean" then
			state.advanced.antiStuckEnabled = settings.antiStuckEnabled
		end
		if isFinite(settings.findSpeedPct) and settings.findSpeedPct >= CONFIG.SpeedMin and settings.findSpeedPct <= CONFIG.SpeedMax then
			state.find.speedPct = settings.findSpeedPct
		end
	end

	if not getSelectedSlot() then
		local list = visibleSlots()
		state.selectedId = list[1] and list[1].id or nil
	end
	if not state.selectedId then
		state.autoReturn = false
	end

	if restored > 0 then
		table.insert(pendingNotices, {
			string.format("Data berhasil dipulihkan: %d posisi.", restored),
			"success",
		})
	end
	if skipped > 0 then
		table.insert(pendingNotices, {
			string.format("%d entri data tidak valid dilewati.", skipped),
			"warning",
		})
	end
end

-- Menyimpan SEMUA data + pengaturan. Aman dipanggil berulang: bila isi tidak berubah, tidak menulis ulang.
-- Setiap penulisan diverifikasi dengan membaca balik file; gagal -> dicoba sekali lagi.
persistSavedData = function()
	if not state.storage.available then
		return false
	end

	local serialized = {}
	for _, slot in ipairs(state.slots) do
		local position = slot.cf.Position
		local _, yaw = slot.cf:ToOrientation()
		table.insert(serialized, {
			id = slot.id,
			name = slot.name,
			placeId = slot.placeId,
			gameId = slot.gameId,
			savedAt = slot.savedAt,
			position = { x = position.X, y = position.Y, z = position.Z },
			yaw = math.deg(yaw),
			cframe = { slot.cf:GetComponents() },
			camera = slot.camRel and { slot.camRel:GetComponents() } or nil,
		})
	end

	local findInteractKeyNames = {}
	for _, category in ipairs(FIND_CATEGORIES) do
		local keyCode = state.find.interactKeys[category.id]
		findInteractKeyNames[category.id] = keyCode and keyCode.Name or "E"
	end

	local payload = {
		version = CONFIG.DataVersion,
		settings = {
			autoReturn = state.autoReturn,
			selectedId = state.selectedId,
			antiAfkKey = state.afk.keyCode.Name,
			antiAfkMinutes = state.afk.minutes,
			antiAfkEnabled = state.afk.active,
			walkSpeedPct = state.walkSpeedPct,
			autoDelay = state.autoDelay,
			autoTrigger = state.autoTrigger,
			findCategories = state.find.categories,
			findCustom = state.find.custom,
			findAvoidWater = state.find.avoidWater,
			findAvoidHazard = state.find.avoidHazard,
			findLoopEnabled = state.find.loopEnabled,
			findMode = state.find.mode,
			findJumpHighCoinGold = state.find.jumpHighCoinGold,
			findInteractEnabled = state.find.interactEnabled,
			findInteractKeys = findInteractKeyNames,
			findSpeedPct = state.find.speedPct,
			findKinds = state.find.kinds,
			findTriggers = state.find.triggers,
			findStandoff = state.find.standoff,
			autoExecuteEnabled = state.advanced.autoExecuteEnabled,
			autoExecuteUrl = state.advanced.scriptUrl,
			antiStuckEnabled = state.advanced.antiStuckEnabled,
		},
		slots = serialized,
	}

	local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
	if not okEncode then
		return false
	end
	if encoded == state.lastEncoded then
		return true
	end

	local function attempt()
		local okWrite = pcall(function()
			if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(CONFIG.DataFolder) then
				makefolder(CONFIG.DataFolder)
			end
			writefile(CONFIG.DataFile, encoded)
		end)
		if not okWrite then
			return false
		end
		local okBack, back = pcall(readfile, CONFIG.DataFile)
		return okBack and type(back) == "string" and #back == #encoded
	end

	if attempt() or attempt() then
		state.lastEncoded = encoded
		return true
	end

	if os.clock() - state.lastPersistError > 5 then
		state.lastPersistError = os.clock()
		notify("Gagal menulis file data. Perubahan hanya berlaku di sesi ini.", "error")
	end
	return false
end

--------------------------------------------------------------------------------
-- ADVANCED: AUTOEXECUTE / REJOIN
--------------------------------------------------------------------------------

local function isValidHttpUrl(value)
	return type(value) == "string"
		and #value > 0
		and #value <= CONFIG.AutoExecuteUrlMaxLength
		and (value:match("^https://") ~= nil or value:match("^http://") ~= nil)
end

local function findQueueOnTeleport()
	local candidates = {
		globalEnv.queue_on_teleport,
		globalEnv.queueonteleport,
		type(globalEnv.syn) == "table" and globalEnv.syn.queue_on_teleport or nil,
		type(globalEnv.fluxus) == "table" and globalEnv.fluxus.queue_on_teleport or nil,
	}
	for _, candidate in pairs(candidates) do
		if type(candidate) == "function" then
			return candidate
		end
	end
	return nil
end

local function queueAutoExecute(resumeFindAfterTeleport)
	local queueFn = findQueueOnTeleport()
	if not queueFn then
		return false, "Executor ini tidak menyediakan queue_on_teleport."
	end

	local payload
	if state.advanced.autoExecuteEnabled then
		local url = state.advanced.scriptUrl
		if not isValidHttpUrl(url) then
			return false, "Masukkan URL raw script berawalan http:// atau https:// terlebih dahulu."
		end
		local quotedUrl = string.format("%q", url)
		payload = string.format([[
local url = %s
local resumeFind = %s
local env = (type(getgenv) == "function" and getgenv()) or _G
env.__IsekaiReturnSystemAutoExecuteManaged = true
env.__IsekaiReturnSystemAutoExecuteEnabled = true
env.__IsekaiReturnSystemAutoExecuteURL = url
env.__IsekaiReturnSystemResumeFindAfterTeleport = resumeFind
local ok, err = pcall(function()
	local source = game:HttpGet(url)
	local chunk, compileError = loadstring(source)
	assert(type(chunk) == "function", tostring(compileError or "loadstring gagal"))
	chunk()
end)
if not ok then
	warn("[IsekaiReturnSystem] Autoexecute gagal: " .. tostring(err))
end
]], quotedUrl, resumeFindAfterTeleport and "true" or "false")
	else
		-- Mengganti antrean sebelumnya dengan no-op jika executor mendukung antrean tunggal.
		payload = "-- Isekai Return System autoexecute disabled\n"
	end

	local ok, err = pcall(queueFn, payload)
	if not ok then
		return false, "Gagal mendaftarkan autoexecute: " .. tostring(err)
	end
	return true, "Autoexecute disiapkan untuk teleport/rejoin berikutnya."
end

local function setAutoExecuteGlobals(enabled, url)
	globalEnv.__IsekaiReturnSystemAutoExecuteManaged = true
	globalEnv.__IsekaiReturnSystemAutoExecuteEnabled = enabled == true
	globalEnv.__IsekaiReturnSystemAutoExecuteURL = type(url) == "string" and url or ""
end

--------------------------------------------------------------------------------
-- SLOT MANAGEMENT
--------------------------------------------------------------------------------

local function getCharacterParts()
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = (humanoid and humanoid.RootPart) or character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, root
end

local function nextDefaultName()
	local used = {}
	for _, slot in ipairs(visibleSlots()) do
		used[slot.name:lower()] = true
	end
	for i = 1, CONFIG.MaxSlots + 1 do
		local candidate = "Save " .. i
		if not used[candidate:lower()] then
			return candidate
		end
	end
	return "Save " .. (#state.slots + 1)
end

local function findSlotByName(name)
	for _, slot in ipairs(visibleSlots()) do
		if slot.name:lower() == name:lower() then
			return slot
		end
	end
	return nil
end

local function savePosition(rawName)
	if state.closed then
		return false
	end
	if state.busy then
		notify("Tunggu perjalanan selesai (atau tekan Stop) sebelum menyimpan.", "info")
		return false
	end

	local character, humanoid, root = getCharacterParts()
	if not character or not humanoid or not root or not root.Parent then
		notify("Karakter belum siap. Coba lagi sebentar.", "warning")
		return false
	end
	if humanoid.Health <= 0 then
		notify("Tidak bisa menyimpan posisi saat karakter mati.", "warning")
		return false
	end

	local cf = root.CFrame
	local position = cf.Position
	if not isFinite(position.X) or not isFinite(position.Y) or not isFinite(position.Z) then
		notify("Posisi tidak valid (koordinat rusak).", "error")
		return false
	end
	if position.Y < Workspace.FallenPartsDestroyHeight + 20 then
		notify("Posisi tidak valid: terlalu dekat dengan batas void.", "error")
		return false
	end

	local humanoidState = humanoid:GetState()
	if humanoidState == Enum.HumanoidStateType.Freefall
		or humanoidState == Enum.HumanoidStateType.Jumping
		or humanoidState == Enum.HumanoidStateType.FallingDown
		or humanoidState == Enum.HumanoidStateType.Ragdoll then
		notify("Tunggu sampai karakter mendarat sebelum menyimpan.", "warning")
		return false
	end
	if humanoid.SeatPart then
		notify("Berdiri dari kursi dulu sebelum menyimpan posisi.", "warning")
		return false
	end

	local list = visibleSlots()
	if #list >= CONFIG.MaxSlots then
		notify(string.format("Slot penuh (%d/%d). Hapus satu slot dulu.", #list, CONFIG.MaxSlots), "warning")
		return false
	end

	local name, nameError = sanitizeName(rawName)
	if not name then
		notify(nameError, "warning")
		return false
	end
	if name == "" then
		name = nextDefaultName()
	elseif findSlotByName(name) then
		notify(string.format("Nama \"%s\" sudah dipakai. Gunakan nama lain.", name), "warning")
		return false
	end

	for _, slot in ipairs(list) do
		if (slot.cf.Position - position).Magnitude < CONFIG.DuplicateDistance
			and slot.cf.LookVector:Dot(cf.LookVector) > 0.99 then
			notify(string.format("Posisi yang sama sudah tersimpan di \"%s\".", slot.name), "info")
			return false
		end
	end

	local camera = Workspace.CurrentCamera
	local camRel = camera and cf:ToObjectSpace(camera.CFrame) or nil

	local slot = {
		id = HttpService:GenerateGUID(false),
		name = name,
		cf = cf,
		camRel = camRel,
		placeId = game.PlaceId,
		gameId = game.GameId,
		savedAt = os.time(),
	}
	table.insert(state.slots, slot)

	local selectedNow = false
	if not getSelectedSlot() then
		state.selectedId = slot.id
		selectedNow = true
	end

	persistSavedData()
	if ui.nameBox then
		ui.nameBox.Text = ""
	end
	refreshUI()

	if selectedNow then
		notify(string.format("Save Position \"%s\" berhasil disimpan dan dipilih.", name), "success")
	else
		notify(string.format("Save Position \"%s\" berhasil disimpan.", name), "success")
	end
	return true
end

local function selectSlot(id)
	if state.closed then
		return
	end
	for _, slot in ipairs(visibleSlots()) do
		if slot.id == id then
			state.selectedId = id
			state.autoPauseUntil = 0
			persistSavedData()
			refreshUI()
			setStatus(string.format("Slot aktif: %s", slot.name), "info")
			return
		end
	end
end

local function deletePosition(id)
	for index, slot in ipairs(state.slots) do
		if slot.id == id and slot.placeId == game.PlaceId then
			table.remove(state.slots, index)
			state.moveToken += 1
			if state.selectedId == id then
				local remaining = visibleSlots()
				state.selectedId = remaining[1] and remaining[1].id or nil
				if not state.selectedId then
					state.autoReturn = false
				end
			end
			persistSavedData()
			refreshUI()
			notify(string.format("Data \"%s\" berhasil dihapus.", slot.name), "success")
			return true
		end
	end
	notify("Slot tidak ditemukan.", "warning")
	return false
end

local function deleteAllPositions()
	local count = #state.slots
	table.clear(state.slots)
	state.selectedId = nil
	state.autoReturn = false
	state.moveToken += 1
	persistSavedData()
	refreshUI()
	notify(string.format("Semua data berhasil dihapus (%d slot).", count), "success")
end

--------------------------------------------------------------------------------
-- TELEPORT / RETURN
--------------------------------------------------------------------------------

local function waitForCharacter(timeout)
	local deadline = os.clock() + timeout
	while not state.closed do
		local character, humanoid, root = getCharacterParts()
		if character and humanoid and root and root.Parent and character:IsDescendantOf(Workspace) then
			return character, humanoid, root
		end
		if os.clock() >= deadline then
			break
		end
		task.wait(0.1)
	end
	return nil, nil, nil
end

-- Mengembalikan CFrame tujuan yang aman, catatan opsional, atau nil + alasan.
local function resolveSafeCFrame(target, character, root)
	local position = target.Position
	if not isFinite(position.X) or not isFinite(position.Y) or not isFinite(position.Z) then
		return nil, "Posisi tujuan tidak valid."
	end
	if position.Y < Workspace.FallenPartsDestroyHeight + 5 then
		return nil, "Posisi tujuan berada di bawah batas void."
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	local ground = Workspace:Raycast(position, Vector3.new(0, -40, 0), rayParams)
	if not ground then
		return nil, "Tidak ada permukaan di bawah posisi tujuan. Teleport dibatalkan agar tidak jatuh."
	end

	local boxCFrame, boxSize = character:GetBoundingBox()
	local offset = root.CFrame:ToObjectSpace(boxCFrame)
	local testSize = Vector3.new(math.max(boxSize.X - 0.4, 0.2), math.max(boxSize.Y - 0.6, 0.2), math.max(boxSize.Z - 0.4, 0.2))

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local lift = 0
	while lift <= CONFIG.MaxLift do
		local candidate = target + Vector3.new(0, lift, 0)
		local parts = Workspace:GetPartBoundsInBox(candidate * offset, testSize, overlapParams)
		local blocked = false
		for _, part in ipairs(parts) do
			if part.CanCollide then
				blocked = true
				break
			end
		end
		if not blocked then
			if lift > 0 then
				return candidate, string.format("Posisi dinaikkan %.1f stud agar tidak menembus objek.", lift)
			end
			return candidate, nil
		end
		lift += CONFIG.LiftStep
	end
	return target, "Posisi tujuan terhalang objek; teleport tetap dilakukan."
end

local function restoreWalkSpeed()
	local walk = state.walk
	state.walk = nil
	if walk and walk.humanoid and walk.humanoid.Parent then
		walk.humanoid.WalkSpeed = walk.original
		local root = walk.humanoid.RootPart
		if root then
			walk.humanoid:MoveTo(root.Position) -- hentikan gerakan yang tersisa
		end
	end
end

-- pct opsional: persentase kecepatan (default = kecepatan Return). Find memakai kecepatannya sendiri.
local function applyWalkSpeed(humanoid, pct)
	pct = pct or state.walkSpeedPct
	local original = humanoid.WalkSpeed
	state.walk = { humanoid = humanoid, original = original }
	if pct ~= 100 then
		humanoid.WalkSpeed = original * pct / 100
	end
end

local function flatten(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Titik di permukaan tanah tepat di bawah tujuan (lebih andal untuk Pathfinding daripada titik di udara).
local function groundGoal(character, position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position or position
end

local STEER_ANGLES = { 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180 }

-- Mencari arah jalan yang terbuka (tidak ada tembok & ada lantai di depan). `sign` menentukan sisi yang dicoba duluan.
local function findOpenDirection(character, root, desired, sign, skipStraight)
	if desired.Magnitude < 0.01 then
		desired = flatten(root.CFrame.LookVector)
	end
	desired = desired.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local origin = root.Position

	local function isOpen(dir)
		for _, height in ipairs({ -2, 0.5, 2 }) do
			if Workspace:Raycast(origin + Vector3.new(0, height, 0), dir * 6, params) then
				return false
			end
		end
		-- harus ada lantai di depan (hindari melangkah ke jurang/void)
		return Workspace:Raycast(origin + dir * 5, Vector3.new(0, -14, 0), params) ~= nil
	end

	if not skipStraight and isOpen(desired) then
		return desired
	end
	for _, angle in ipairs(STEER_ANGLES) do
		local dir = CFrame.Angles(0, math.rad(angle * sign), 0):VectorToWorldSpace(desired)
		if isOpen(dir) then
			return dir
		end
	end
	return nil
end

local function isSeated(humanoid)
	return humanoid.SeatPart ~= nil or humanoid.Sit
end

-- Keluar dari kursi dengan MELONCAT (seperti pemain sungguhan). Hanya jika meloncat tidak berhasil
-- dalam 4 detik, Sit dimatikan langsung.
local function leaveSeat(humanoid, cancelled)
	local deadline = os.clock() + 4
	local attempt = 0
	while isSeated(humanoid) and os.clock() < deadline do
		if cancelled() then
			return false
		end
		attempt += 1
		humanoid.Jump = true
		if attempt % 3 == 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		task.wait(0.35)
	end
	if cancelled() then
		return false
	end
	if isSeated(humanoid) then
		humanoid.Sit = false
		task.wait(0.2)
	end
	task.wait(0.25)
	return not isSeated(humanoid)
end

-- Teleport langsung (HANYA cadangan setelah batas waktu berjalan habis).
local function teleportToSlot(slot, character, humanoid, root, token, restoreCamera)
	local target, note = resolveSafeCFrame(slot.cf, character, root)
	if not target then
		return false, note, "error"
	end
	if state.closed or token ~= state.moveToken then
		return false, nil, nil
	end

	if humanoid.SeatPart then
		humanoid.Sit = false
		RunService.Heartbeat:Wait()
		if state.closed or token ~= state.moveToken or player.Character ~= character or not root.Parent then
			return false, nil, nil
		end
	end

	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	RunService.Heartbeat:Wait()

	if state.closed or player.Character ~= character or not root.Parent then
		return false, nil, nil
	end
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local camera = Workspace.CurrentCamera
	if restoreCamera and camera and slot.camRel and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = target * slot.camRel
		RunService.RenderStepped:Wait()
		camera.CameraType = Enum.CameraType.Custom
	end

	return true, note, note and "warning" or nil
end

-- Menghitung rute. Mencoba beberapa variasi ukuran agen agar celah sempit / tepi tembok tidak menggagalkan rute.
-- options (opsional, dipakai Find): { avoidWater = bool, validate = function(waypoints) -> bool }
local function computeWaypoints(root, humanoid, goal, radiusBoost, options)
	local baseRadius = math.max(2, root.Size.X / 2 + 0.5)
	local height = math.max(5, root.Size.Y + humanoid.HipHeight * 2)
	local variants = {
		{ radius = baseRadius + radiusBoost, climb = true },
		{ radius = math.max(1, baseRadius - 0.8), climb = true },
		{ radius = baseRadius + radiusBoost + 1.5, climb = false },
	}
	for _, variant in ipairs(variants) do
		local params = {
			AgentRadius = variant.radius,
			AgentHeight = height,
			AgentCanJump = true,
			AgentCanClimb = variant.climb,
			WaypointSpacing = 4,
		}
		if options and options.avoidWater then
			params.Costs = { Water = math.huge } -- air tidak boleh dilewati
		end
		local path = PathfindingService:CreatePath(params)
		local ok = pcall(function()
			path:ComputeAsync(root.Position, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			if #waypoints >= 2 then
				if not (options and options.validate) or options.validate(waypoints) then
					return waypoints
				end
			end
		end
	end
	return nil
end

-- Mengembalikan: ada penghalang setinggi lutut, ada penghalang setinggi kepala.
local function checkObstacle(character, root, direction)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local origin = root.Position
	local low = Workspace:Raycast(origin + Vector3.new(0, -2, 0), direction * 3, params)
	local high = Workspace:Raycast(origin + Vector3.new(0, 1.4, 0), direction * 3, params)
	return low ~= nil, high ~= nil
end

local function performWalk(slot, token, source)
	local character, humanoid, root = waitForCharacter(8)
	if not root then
		return false, "Karakter belum siap. Perjalanan dibatalkan.", "warning"
	end
	if humanoid.Health <= 0 then
		return false, "Karakter sedang mati. Perjalanan dibatalkan.", "warning"
	end

	local targetCF = slot.cf
	local targetPos = targetCF.Position
	if not isFinite(targetPos.X) or not isFinite(targetPos.Y) or not isFinite(targetPos.Z)
		or targetPos.Y < Workspace.FallenPartsDestroyHeight + 5 then
		return false, "Posisi tujuan tidak valid.", "error"
	end

	local function cancelled()
		return state.closed or token ~= state.moveToken or player.Character ~= character
			or not root.Parent or humanoid.Health <= 0
	end

	-- Sedang duduk? Meloncat keluar dulu.
	if isSeated(humanoid) then
		setStatus("Karakter sedang duduk, meloncat keluar dari kursi...", "info")
		leaveSeat(humanoid, cancelled)
		if cancelled() then
			return false, nil, nil
		end
	end

	applyWalkSpeed(humanoid)

	local goalPos = groundGoal(character, targetPos)
	local startTime = os.clock()
	local anchorPos = root.Position -- acuan "tidak bergeser"
	local anchorTime = startTime
	local progressTime = startTime -- terakhir kali ada kemajuan nyata
	local bestDist = flatten(targetPos - root.Position).Magnitude
	local waypoints = nil
	local wpIndex = 2
	local lastWpIndex = 2
	local jumpedIndex = 0
	local lastRepath = -math.huge
	local forceRepath = false
	local radiusBoost = 0
	local frozenLevel = 0
	local noProgressLevel = 0
	local lastJump = 0
	local steerDir = nil
	local steerUntil = 0
	local steerSign = 1
	local detourPos = nil
	local detourUntil = 0

	local function startSidestep(now)
		steerSign = -steerSign
		local desired = flatten(targetPos - root.Position)
		if desired.Magnitude < 0.1 then
			desired = flatten(root.CFrame.LookVector)
		end
		local dir = findOpenDirection(character, root, desired, steerSign, true)
		if not dir then
			dir = -desired.Unit -- semua arah tertutup: mundur sebentar
		end
		steerDir = dir
		steerUntil = now + 1.2
	end

	local function startDetour(now)
		local angle = math.random(0, 359)
		local desired = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(Vector3.new(0, 0, -1))
		steerSign = -steerSign
		local dir = findOpenDirection(character, root, desired, steerSign, false)
		if dir then
			detourPos = root.Position + dir * 18
			detourUntil = now + 5
		end
	end

	local function tryJump(now)
		if now - lastJump >= 0.8 and humanoid.FloorMaterial ~= Enum.Material.Air then
			humanoid.Jump = true
			lastJump = now
		end
	end

	while true do
		if cancelled() then
			return false, nil, nil
		end
		local now = os.clock()
		local pos = root.Position
		local toTarget = targetPos - pos
		local flatDist = flatten(toTarget).Magnitude

		if flatDist <= CONFIG.ArriveDistance and math.abs(toTarget.Y) <= 4 then
			break
		end

		-- Duduk lagi di tengah jalan (mis. menyentuh kursi)? Meloncat keluar.
		if isSeated(humanoid) then
			leaveSeat(humanoid, cancelled)
			if cancelled() then
				return false, nil, nil
			end
			anchorPos = root.Position
			anchorTime = os.clock()
			continue
		end

		-- Deteksi bergeser (frozen) dan kemajuan nyata (progress).
		if (pos - anchorPos).Magnitude >= 1 then
			anchorPos = pos
			anchorTime = now
			frozenLevel = 0
		end
		if flatDist < bestDist - 2 or wpIndex > lastWpIndex then
			bestDist = math.min(bestDist, flatDist)
			lastWpIndex = wpIndex
			progressTime = now
			noProgressLevel = 0
			radiusBoost = 0
		end
		local frozen = now - anchorTime
		local noProgress = now - progressTime
		local elapsed = now - startTime

		-- Teleport = cadangan terakhir: hanya setelah batas waktu habis DAN (masih jauh ATAU nyangkut).
		-- Jika sudah dekat dan masih terus bergerak, diberi tambahan waktu sampai batas mutlak.
		if elapsed >= CONFIG.WalkMaxTime then
			local far = flatDist > CONFIG.FarDistance
			local stuck = frozen >= CONFIG.StuckConfirm
			if far or stuck or elapsed >= CONFIG.WalkHardMax then
				humanoid:MoveTo(root.Position)
				local ok, note, kind = teleportToSlot(slot, character, humanoid, root, token, source == "manual")
				if ok then
					return true, string.format("Batas waktu jalan %d detik habis dan karakter belum sampai (jauh/tersangkut), jadi dipindahkan langsung.", CONFIG.WalkMaxTime), "warning"
				end
				return false, note, kind
			end
		end

		-- Pemulihan bertahap saat tidak bergeser: loncat -> menyamping -> rute ulang -> memutar.
		if frozen >= 1.2 then
			tryJump(now)
		end
		if frozenLevel == 0 and frozen >= 2.5 then
			frozenLevel = 1
			startSidestep(now)
		elseif frozenLevel == 1 and frozen >= 4.5 then
			frozenLevel = 2
			radiusBoost += 1
			forceRepath = true
			startSidestep(now)
		elseif frozenLevel == 2 and frozen >= 7 then
			frozenLevel = 3
			radiusBoost += 1
			forceRepath = true
			startDetour(now)
		elseif frozenLevel >= 3 and frozen >= 7 + (frozenLevel - 2) * 5 then
			frozenLevel += 1
			forceRepath = true
			startDetour(now)
		end

		-- Bergerak tapi tidak maju (berputar-putar): rute ulang dengan ukuran agen berbeda, sesekali memutar.
		if noProgress >= 10 * (noProgressLevel + 1) then
			noProgressLevel += 1
			radiusBoost = noProgressLevel % 3
			forceRepath = true
			if noProgressLevel % 2 == 0 then
				startDetour(now)
			end
		end

		-- Hitung ulang rute secara berkala atau saat dipaksa.
		if forceRepath or now - lastRepath >= (waypoints and 8 or 5) then
			lastRepath = now
			forceRepath = false
			waypoints = computeWaypoints(root, humanoid, goalPos, radiusBoost)
			wpIndex = 2
			lastWpIndex = 2
			jumpedIndex = 0
			continue
		end

		-- Tentukan titik tujuan langkah ini.
		local moveTarget = nil
		local freeRoam = false -- true = tanpa rute, penghindaran halangan ditangani langsung
		if now < steerUntil and steerDir then
			moveTarget = pos + steerDir * 8
		elseif detourPos then
			if now >= detourUntil or flatten(detourPos - pos).Magnitude < 3 then
				detourPos = nil
				forceRepath = true
			else
				moveTarget = detourPos
				freeRoam = true
			end
		end
		if not moveTarget then
			if waypoints then
				while waypoints[wpIndex]
					and flatten(waypoints[wpIndex].Position - pos).Magnitude < 3
					and math.abs(waypoints[wpIndex].Position.Y - pos.Y) < 7 do
					wpIndex += 1
				end
				local waypoint = waypoints[wpIndex]
				if waypoint then
					moveTarget = waypoint.Position
					if waypoint.Action == Enum.PathWaypointAction.Jump and jumpedIndex ~= wpIndex then
						jumpedIndex = wpIndex
						tryJump(now)
					end
					-- Terdorong jauh dari rute: hitung ulang.
					if flatten(moveTarget - pos).Magnitude > 16 and now - lastRepath >= 2 then
						forceRepath = true
					end
				else
					moveTarget = targetPos
				end
			else
				moveTarget = targetPos
				freeRoam = true
			end
		end

		-- Penghalang di depan: loncat jika rendah, cari arah terbuka jika tembok (tanpa rute).
		local direction = flatten(moveTarget - pos)
		if direction.Magnitude > 0.1 then
			local low, high = checkObstacle(character, root, direction.Unit)
			if low and not high then
				tryJump(now)
			elseif low and high and freeRoam then
				steerSign = -steerSign
				local open = findOpenDirection(character, root, direction, steerSign, true)
				if open then
					steerDir = open
					steerUntil = now + 0.8
				end
			end
		end

		humanoid:MoveTo(moveTarget)
		task.wait(0.1)
	end

	-- Pendekatan akhir ke titik yang tepat.
	local finalDeadline = os.clock() + 2
	while os.clock() < finalDeadline do
		if cancelled() then
			return false, nil, nil
		end
		if flatten(targetPos - root.Position).Magnitude <= 0.7 then
			break
		end
		humanoid:MoveTo(targetPos)
		task.wait(0.1)
	end
	if cancelled() then
		return false, nil, nil
	end

	-- Koreksi kecil agar posisi dan arah hadap sama persis dengan yang disimpan.
	if (root.Position - targetPos).Magnitude <= 3.5 then
		root.CFrame = targetCF
	else
		root.CFrame = CFrame.new(root.Position) * (targetCF - targetCF.Position)
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local camera = Workspace.CurrentCamera
	if source == "manual" and camera and slot.camRel and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = targetCF * slot.camRel
		RunService.RenderStepped:Wait()
		camera.CameraType = Enum.CameraType.Custom
	end

	return true, nil, nil
end

moveToSavedSpot = function(slot, source)
	if state.closed then
		return false
	end
	if not slot then
		notify("Pilih slot posisi terlebih dahulu.", "warning")
		return false
	end
	if state.busy then
		if source == "manual" then
			notify("Perjalanan masih berjalan. Tekan Stop untuk membatalkan.", "info")
		end
		return false
	end

	state.busy = true
	state.moveToken += 1
	local token = state.moveToken
	setStatus(string.format("Berjalan menuju \"%s\"...", slot.name), "info")
	refreshUI()

	local ok, success, message, kind = pcall(performWalk, slot, token, source)
	restoreWalkSpeed()
	state.busy = false

	if state.closed then
		return false
	end
	refreshUI()
	if not ok then
		state.autoPauseUntil = os.clock() + 5
		notify("Perjalanan gagal karena error internal.", "error")
		warn("[IsekaiReturnSystem] performWalk error: " .. tostring(success))
		return false
	end
	if success then
		state.autoPauseUntil = os.clock() + 2
		local prefix = source == "auto" and "Auto Return: tiba di" or "Tiba di"
		notify(string.format("%s \"%s\".", prefix, slot.name), "success")
		if message then
			notify(message, "warning")
		end
		return true
	end
	-- Gagal/dibatalkan: beri jeda agar Auto Return tidak mengulang tanpa henti.
	state.autoPauseUntil = os.clock() + 5
	if message then
		notify(message, kind or "warning")
	end
	return false
end

local function cancelMove()
	if not state.busy then
		return
	end
	state.moveToken += 1
	state.autoPauseUntil = os.clock() + math.max(state.autoDelay, 3)
	notify("Perjalanan dibatalkan.", "info")
end

toggleAutoReturn = function()
	if state.closed then
		return
	end
	if not state.autoReturn then
		if not getSelectedSlot() then
			notify("Pilih atau simpan slot dulu sebelum mengaktifkan Auto Return.", "warning")
			return
		end
		state.autoReturn = true
		state.autoPauseUntil = 0
		persistSavedData()
		refreshUI()
		notify(string.format("Auto Return aktif. Karakter otomatis kembali ke slot terpilih jika bergeser lebih dari %.1f stud.", state.autoTrigger), "success")
	else
		state.autoReturn = false
		persistSavedData()
		refreshUI()
		notify("Auto Return dimatikan.", "info")
	end
end

-- Pemantau Auto Return: selama aktif, jika karakter berada lebih jauh dari "jarak deteksi" dari slot
-- terpilih (karena respawn, terdorong, teleport game, dsb.), tunggu jeda lalu berjalan kembali
-- dengan logika yang sama persis seperti tombol Return manual.
local function runAutoReturnWatcher()
	local awaySince = nil
	local waitFor = 0
	while not state.closed do
		task.wait(CONFIG.WatchInterval)
		if state.closed then
			return
		end

		local findActive = state.find.running or state.find.scanning
		local slot = (state.autoReturn and not state.busy and not findActive) and getSelectedSlot() or nil
		local character, humanoid, root = nil, nil, nil
		if slot then
			character, humanoid, root = getCharacterParts()
		end
		if not slot or not character or not humanoid or not root or not root.Parent
			or humanoid.Health <= 0 or not character:IsDescendantOf(Workspace) then
			awaySince = nil
			continue
		end

		local now = os.clock()
		if now < state.autoPauseUntil then
			awaySince = nil
			continue
		end

		local distance = (root.Position - slot.cf.Position).Magnitude
		if distance <= state.autoTrigger then
			awaySince = nil
		elseif not awaySince then
			awaySince = now
			local delaySeconds = state.autoDelay
			if delaySeconds > 0 then
				-- Jeda diacak +-20% agar tidak terlihat seperti pola tetap.
				waitFor = delaySeconds * (0.8 + math.random() * 0.4)
				notify(string.format("Auto Return: posisi bergeser %.1f stud, kembali ke \"%s\" dalam %.0f detik.", distance, slot.name, waitFor), "info")
			else
				waitFor = 0.3
			end
		elseif now - awaySince >= waitFor then
			awaySince = nil
			moveToSavedSpot(slot, "auto")
		end
	end
end

local function onCharacterRemoving()
	state.moveToken += 1
end

--------------------------------------------------------------------------------
-- FIND (cari item + jalan otomatis berurutan)
--------------------------------------------------------------------------------

-- Memecah nama objek jadi kata: "GoldCoin_12" -> { "gold", "coin" }.
local function tokenize(name)
	local spaced = name:gsub("(%l)(%u)", "%1 %2"):gsub("[^%a]+", " "):lower()
	local tokens = {}
	for word in spaced:gmatch("%S+") do
		table.insert(tokens, word)
	end
	return tokens
end

-- Kata cocok jika sama persis (boleh +s), atau (jika diizinkan) menjadi awalan kata panjang ("golden").
local function tokenHas(tokens, word, allowPrefix)
	local wordLength = #word
	for _, token in ipairs(tokens) do
		if token == word or token == word .. "s" then
			return true
		end
		if allowPrefix and wordLength >= 4 and #token > wordLength and token:sub(1, wordLength) == word then
			return true
		end
	end
	return false
end

local function matchName(name, matchers)
	local lowered = name:lower()
	local tokens = nil
	for _, matcher in ipairs(matchers) do
		for _, word in ipairs(matcher.words) do
			if lowered:find(word, 1, true) then
				if matcher.custom then
					return matcher -- kata kunci manual: cukup mengandung teks tsb
				end
				tokens = tokens or tokenize(name)
				if tokenHas(tokens, word, true) then
					return matcher
				end
			end
		end
	end
	return nil
end

-- Nama objek, atau nama Folder/Model induknya (mis. Workspace.Coins.Part).
-- Pencocokan lewat Model induk hanya dipakai bila hasilnya wajib punya pemicu ambil (lihat buildEntry).
local function matchInstance(inst, matchers, allowModelParent)
	local matcher = matchName(inst.Name, matchers)
	if matcher then
		return matcher, false
	end
	local parent = inst.Parent
	if parent and parent ~= Workspace then
		local allowed = parent:IsA("Folder")
			or (allowModelParent and parent:IsA("Model") and not parent:FindFirstChildOfClass("Humanoid"))
		if allowed then
			local parentMatcher = matchName(parent.Name, matchers)
			if parentMatcher then
				return parentMatcher, parent:IsA("Model") and "model" or "folder"
			end
		end
	end
	return nil, false
end


local function hazardName(name)
	local lowered = name:lower()
	local possible = false
	for _, word in ipairs(HAZARD_WORDS) do
		if lowered:find(word, 1, true) then
			possible = true
			break
		end
	end
	if not possible then
		return false
	end
	local tokens = tokenize(name)
	for _, word in ipairs(HAZARD_WORDS) do
		if tokenHas(tokens, word, false) then
			return true
		end
	end
	return false
end

local function isHazardInstance(inst)
	if hazardName(inst.Name) then
		return true
	end
	local parent = inst.Parent
	if parent and parent ~= Workspace and (parent:IsA("Folder") or parent:IsA("Model")) then
		return hazardName(parent.Name)
	end
	return false
end

-- Jarak titik ke kotak part (0 jika di dalam). Aman untuk part raksasa seperti lantai lava.
local function distToPart(part, point)
	local rel = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	local dx = math.max(math.abs(rel.X) - half.X, 0)
	local dy = math.max(math.abs(rel.Y) - half.Y, 0)
	local dz = math.max(math.abs(rel.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function nearHazard(point, margin)
	for _, part in ipairs(state.find.hazards) do
		if part.Parent and distToPart(part, point) <= margin then
			return true
		end
	end
	return false
end

local function waypointsHitHazard(waypoints)
	for _, waypoint in ipairs(waypoints) do
		if nearHazard(waypoint.Position, CONFIG.HazardMargin) then
			return true
		end
	end
	return false
end

-- Apakah titik ini berada di dalam voxel air Terrain.
local function pointInWater(position)
	local ok, result = pcall(function()
		local terrain = Workspace.Terrain
		local cell = terrain:WorldToCell(position)
		local minCorner = cell * 4
		local region = Region3.new(minCorner, minCorner + Vector3.new(4, 4, 4))
		local materials, occupancy = terrain:ReadVoxels(region, 4)
		return materials[1][1][1] == Enum.Material.Water and occupancy[1][1][1] > 0.2
	end)
	return ok and result == true
end

-- Apakah permukaan pertama di bawah titik adalah air (objek melayang di atas kolam/laut).
local function waterBelow(position, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = false
	local hit = Workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -14, 0), params)
	return hit ~= nil and hit.Material == Enum.Material.Water
end

local function groundBelow(position, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return Workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -150, 0), params) ~= nil
end

local function parseKeywords(text)
	local words, seen = {}, {}
	for piece in tostring(text):gmatch("[^,;\n]+") do
		local word = piece:match("^%s*(.-)%s*$"):lower()
		if #word >= 2 and #word <= 24 and not seen[word] then
			seen[word] = true
			table.insert(words, word)
			if #words >= CONFIG.FindMaxKeywords then
				break
			end
		end
	end
	return words
end

local function buildMatchers()
	local find = state.find
	local matchers = {}
	for _, category in ipairs(FIND_CATEGORIES) do
		if find.categories[category.id] then
			table.insert(matchers, { id = category.id, label = category.label, words = category.words })
		end
	end
	local custom = parseKeywords(find.custom)
	if #custom > 0 then
		table.insert(matchers, { id = "custom", label = "Manual", words = custom, custom = true })
	end
	return matchers
end

local function isCoinOrGoldEntry(entry)
	if entry.id == "coin" or entry.id == "gold" then
		return true
	end
	local name = tostring(entry.name or ""):lower()
	return name:find("coin", 1, true) ~= nil
		or name:find("koin", 1, true) ~= nil
		or name:find("gold", 1, true) ~= nil
		or name:find("emas", 1, true) ~= nil
end

local function entryPosition(entry)
	local visual = entry.visual
	if visual and visual.Parent then
		return visual.Position
	end
	local inst = entry.inst
	if inst and inst.Parent and inst:IsA("Model") then
		local ok, pivot = pcall(inst.GetPivot, inst)
		if ok then
			return pivot.Position
		end
	end
	return nil
end

-- Target masih ada? (hilang / transparan penuh = sudah diambil)
local function entryAlive(entry)
	local inst = entry.inst
	if not inst or not inst.Parent or not inst:IsDescendantOf(Workspace) then
		return false
	end
	local visual = entry.visual
	if visual then
		if not visual.Parent or not visual:IsDescendantOf(Workspace) then
			return false
		end
		if visual.Transparency >= CONFIG.FindMaxTransparency then
			return false
		end
	end
	return true
end

-- Objek di dalam target lain yang sudah terdaftar, atau di dalam karakter (pemain / NPC), diabaikan.
local function insideBlocked(inst, registered)
	local current = inst.Parent
	while current and current ~= Workspace do
		if registered[current] then
			return true
		end
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return true
		end
		current = current.Parent
	end
	return false
end

-- Pemicu yang membuat sebuah objek benar-benar BISA DIAMBIL: ProximityPrompt, ClickDetector,
-- TouchInterest (Touched), atau Tool. Objek tanpa pemicu biasanya hanya dekorasi bernama "Gold".
local function inspectTriggers(inst, kind)
	local prompt, click, touch = false, false, false
	local function inspect(object)
		if object:IsA("ProximityPrompt") then
			if object.Enabled then
				prompt = true
			end
		elseif object:IsA("ClickDetector") then
			click = true
		elseif object:IsA("TouchTransmitter") then
			touch = true
		end
	end
	if kind == "part" then
		for _, child in ipairs(inst:GetChildren()) do
			inspect(child)
		end
	else
		for _, descendant in ipairs(inst:GetDescendants()) do
			inspect(descendant)
		end
	end
	if kind == "tool" then
		touch = true -- Tool diambil dengan menyentuh Handle
	end
	return prompt, click, touch
end

local function describeEntryType(entry)
	local text = entry.kind == "tool" and "Tool" or (entry.kind == "model" and "Model" or "Part")
	if entry.prompt then
		text ..= "+Prompt"
	end
	if entry.click then
		text ..= "+Click"
	end
	if entry.touch and entry.kind ~= "tool" then
		text ..= "+Touch"
	end
	return text
end

local function entryHasTrigger(entry)
	return entry.prompt == true or entry.click == true or entry.touch == true
end

local function buildEntry(inst, matcher, needTrigger)
	local visual = nil
	local kind = "part"
	if inst:IsA("BasePart") then
		local size = inst.Size
		if math.max(size.X, size.Y, size.Z) > CONFIG.FindMaxSize then
			return nil
		end
		if inst.Transparency >= CONFIG.FindMaxTransparency then
			return nil
		end
		visual = inst
	elseif inst:IsA("Tool") then
		kind = "tool"
		local handle = inst:FindFirstChild("Handle")
		if not (handle and handle:IsA("BasePart")) then
			handle = inst:FindFirstChildWhichIsA("BasePart", true)
		end
		if not handle or handle.Transparency >= CONFIG.FindMaxTransparency then
			return nil
		end
		visual = handle
	else
		kind = "model"
		if inst:FindFirstChildOfClass("Humanoid") then
			return nil
		end
		local okSize, extents = pcall(inst.GetExtentsSize, inst)
		if not okSize or math.max(extents.X, extents.Y, extents.Z) > CONFIG.FindMaxSize then
			return nil
		end
		visual = inst.PrimaryPart
		if not visual or visual.Transparency >= CONFIG.FindMaxTransparency then
			visual = nil
			for _, descendant in ipairs(inst:GetDescendants()) do
				if descendant:IsA("BasePart") and descendant.Transparency < CONFIG.FindMaxTransparency then
					visual = descendant
					break
				end
			end
		end
		if not visual then
			return nil
		end
	end

	local position = visual.Position
	if not isFinite(position.X) or not isFinite(position.Y) or not isFinite(position.Z) then
		return nil
	end
	if position.Y < Workspace.FallenPartsDestroyHeight + 5 then
		return nil
	end

	local prompt, click, touch = inspectTriggers(inst, kind)
	if needTrigger and not (prompt or click or touch) then
		return nil
	end
	local entry = {
		inst = inst,
		visual = visual,
		name = string.sub(inst.Name, 1, 24),
		id = matcher.id,
		label = matcher.label,
		kind = kind,
		prompt = prompt,
		click = click,
		touch = touch,
	}
	entry.typeText = describeEntryType(entry)
	return entry
end

local function isDuplicate(found, entry)
	local position = entry.visual.Position
	for _, other in ipairs(found) do
		if (other.visual.Position - position).Magnitude < 1 then
			return true
		end
	end
	return false
end

local function describeCounts()
	local find = state.find
	local parts = {}
	for _, matcher in ipairs(find.matchers) do
		local count = find.counts[matcher.id] or 0
		if count > 0 then
			table.insert(parts, string.format("%s %d", matcher.label, count))
		end
	end
	if #parts == 0 then
		return "-"
	end
	return table.concat(parts, " • ")
end

-- Memindai Workspace. Mengembalikan { entries, hazards, matchers, truncated } atau nil bila dibatalkan / tanpa kriteria.
-- Hasil mentah mencakup SEMUA objek yang cocok nama; saringan tipe dipasang terpisah di applyFilters.
local function scanTargets(token, silent)
	local find = state.find
	local matchers = buildMatchers()
	if #matchers == 0 then
		if not silent then
			notify("Pilih minimal satu kategori atau isi kata kunci manual.", "warning")
		end
		return nil
	end

	local found, registered, hazards = {}, {}, {}
	local truncated = false
	local terrain = Workspace.Terrain
	local scanHazards = find.avoidHazard
	local allowModelParent = not find.triggers.plain
	local list = Workspace:GetDescendants()

	for index, inst in ipairs(list) do
		if index % 1000 == 0 then
			task.wait() -- jangan bekukan game saat memindai peta besar
			if state.closed or find.token ~= token then
				return nil
			end
		end

		local isPart = inst:IsA("BasePart")
		if (isPart or inst:IsA("Model") or inst:IsA("Tool")) and inst ~= terrain then
			if scanHazards and isPart and #hazards < 600 and isHazardInstance(inst) then
				table.insert(hazards, inst)
			end
			if not truncated then
				local matcher, viaParent = matchInstance(inst, matchers, allowModelParent)
				if matcher and not insideBlocked(inst, registered) then
					local entry = buildEntry(inst, matcher, viaParent == "model")
					if entry and not isDuplicate(found, entry) then
						registered[inst] = true
						table.insert(found, entry)
						if #found >= CONFIG.FindMaxRaw then
							truncated = true
						end
					end
				end
			end
		end
	end

	return { entries = found, hazards = hazards, matchers = matchers, truncated = truncated }
end

-- Lolos saringan "Jenis objek" (Part/Model/Tool) dan "Pemicu ambil" (Prompt/Click/Touch/Tanpa pemicu)?
local function passesTypeFilter(entry)
	local find = state.find
	if not find.kinds[entry.kind] then
		return false
	end
	if not entryHasTrigger(entry) then
		return find.triggers.plain == true
	end
	return (entry.prompt and find.triggers.prompt)
		or (entry.click and find.triggers.click)
		or (entry.touch and find.triggers.touch)
		or false
end

-- Menyaring hasil mentah menjadi find.results + menghitung jumlah per kategori / jenis / pemicu.
local function applyFilters()
	local find = state.find
	local results, counts = {}, {}
	local kindCounts = { part = 0, model = 0, tool = 0 }
	local trigCounts = { prompt = 0, click = 0, touch = 0, plain = 0 }
	for _, entry in ipairs(find.raw) do
		kindCounts[entry.kind] += 1
		if entry.prompt then
			trigCounts.prompt += 1
		end
		if entry.click then
			trigCounts.click += 1
		end
		if entry.touch then
			trigCounts.touch += 1
		end
		if not entryHasTrigger(entry) then
			trigCounts.plain += 1
		end
		if passesTypeFilter(entry) and #results < CONFIG.FindMaxResults then
			table.insert(results, entry)
			counts[entry.id] = (counts[entry.id] or 0) + 1
		end
	end
	find.results = results
	find.counts = counts
	find.kindCounts = kindCounts
	find.trigCounts = trigCounts
end

local function applyScan(scan)
	local find = state.find
	find.raw = scan.entries
	find.hazards = scan.hazards
	find.matchers = scan.matchers
	find.truncated = scan.truncated
	find.scanned = true
	applyFilters()
end

-- Alasan target tidak aman (sesuai toggle), atau nil jika aman.
local function entryUnsafeReason(entry, character)
	local find = state.find
	local position = entryPosition(entry)
	if not position then
		return "gone"
	end
	local exclude = { character, entry.inst }
	if find.avoidWater and (pointInWater(position) or waterBelow(position, exclude)) then
		return "water"
	end
	if find.avoidHazard then
		if nearHazard(position, CONFIG.HazardTargetMargin) or not groundBelow(position, exclude) then
			return "hazard"
		end
	end
	return nil
end

-- Titik tujuan untuk Pathfinding: permukaan padat tepat di bawah objek.
local function pathGoal(character, entry, position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, entry.inst }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -60, 0), params)
	return hit and hit.Position or position
end

-- Beberapa game butuh interaksi (tekan E / klik); dipakai hanya jika executor menyediakan fungsinya.
local function activateTarget(entry)
	local inst = entry.inst
	local find = state.find
	local categoryId = entry.id

	-- Untuk kata kunci manual, tebak kategori dari nama item agar toggle/keybind tetap berlaku.
	if categoryId == "custom" then
		local loweredName = tostring(entry.name or ""):lower()
		for _, category in ipairs(FIND_CATEGORIES) do
			if find.interactEnabled[category.id] then
				for _, word in ipairs(category.words) do
					if loweredName:find(word, 1, true) then
						categoryId = category.id
						break
					end
				end
			end
			if categoryId ~= "custom" then
				break
			end
		end
	end

	-- Toggle kategori mengontrol seluruh auto-interaksi: keybind, ProximityPrompt, dan ClickDetector.
	if not find.interactEnabled[categoryId] then
		return
	end
	local interactionKey = find.interactKeys[categoryId]
	if interactionKey and pressKey then
		pressKey(interactionKey)
	end
	if type(fireproximityprompt) == "function" then
		local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt and prompt.Enabled then
			pcall(fireproximityprompt, prompt)
		end
	end
	if type(fireclickdetector) == "function" then
		local detector = inst:FindFirstChildWhichIsA("ClickDetector", true)
		if detector then
			pcall(fireclickdetector, detector)
		end
	end
end

-- Teleport langsung ke objek (cadangan saat jalan tersangkut).
local function teleportToTarget(entry, ctx, cancelled)
	local humanoid, root = ctx.humanoid, ctx.root
	local position = entryPosition(entry)
	if not position then
		return false
	end
	if humanoid.SeatPart then
		humanoid.Sit = false
		RunService.Heartbeat:Wait()
	end
	if cancelled() then
		return false
	end
	local target = CFrame.new(position + Vector3.new(0, 2.5, 0)) * (root.CFrame - root.CFrame.Position)
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	RunService.Heartbeat:Wait()
	if cancelled() then
		return false
	end
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

--------------------------------------------------------------------------------
-- PENDEKATAN TARGET: teleport berjarak, jalan, loncat, berenang, bolak-balik
--------------------------------------------------------------------------------

local function isSwimming(humanoid)
	return humanoid:GetState() == Enum.HumanoidStateType.Swimming
end

-- Loncat (dengan jeda antar-loncatan) hanya bila karakter menapak.
local function ctxJump(ctx)
	local now = os.clock()
	if now - (ctx.lastJump or -math.huge) >= 0.8 and ctx.humanoid.FloorMaterial ~= Enum.Material.Air then
		ctx.humanoid.Jump = true
		ctx.lastJump = now
	end
end

-- Item Coin/Gold boleh dikejar dengan lompatan hanya bila toggle "Jump Coin/Gold" aktif.
local function shouldJumpFor(entry)
	return not isCoinOrGoldEntry(entry) or state.find.jumpHighCoinGold
end

-- Berenang 3D ke titik tujuan (naik/turun mengikuti item). Karakter otomatis mengapung ke permukaan,
-- jadi kecepatan diatur langsung tiap frame agar bisa menyelam ke arah item.
local function swimStep(ctx, destination)
	local humanoid, root = ctx.humanoid, ctx.root
	local toTarget = destination - root.Position
	local distance = toTarget.Magnitude
	if distance < 0.4 then
		return
	end
	local speed = math.max(16, humanoid.WalkSpeed)
	root.AssemblyLinearVelocity = toTarget.Unit * math.min(speed, distance * 8 + 4)
	humanoid:MoveTo(Vector3.new(destination.X, root.Position.Y, destination.Z))
end

local STANDOFF_ANGLES = { 0, 35, -35, 70, -70, 110, -110, 150, -150, 180 }

-- Titik berdiri/berenang "distance" stud dari item (bukan tepat di item). Di darat: permukaan padat dan aman.
-- Di air: titik di dalam air pada kedalaman item. Mengembalikan Vector3 atau nil.
local function pickStandoff(entry, ctx, distance)
	local find = state.find
	local itemPos = entryPosition(entry)
	if not itemPos then
		return nil
	end
	local character, root = ctx.character, ctx.root
	local underwater = pointInWater(itemPos)

	-- Arah awal: dari item menuju posisi karakter sekarang (sisi yang paling mungkin terjangkau).
	local away = flatten(root.Position - itemPos)
	if away.Magnitude < 1 then
		away = Vector3.new(0, 0, 1)
	end
	away = away.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, entry.inst }
	params.RespectCanCollide = true
	local waterFreeParams = RaycastParams.new()
	waterFreeParams.FilterType = Enum.RaycastFilterType.Exclude
	waterFreeParams.FilterDescendantsInstances = { character, entry.inst }
	waterFreeParams.RespectCanCollide = true
	waterFreeParams.IgnoreWater = true

	for _, angle in ipairs(STANDOFF_ANGLES) do
		local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(away)
		local flat = itemPos + direction * distance
		if underwater then
			local point = Vector3.new(flat.X, itemPos.Y, flat.Z)
			if pointInWater(point) and not Workspace:Raycast(itemPos, point - itemPos, waterFreeParams) then
				return point
			end
		else
			local origin = Vector3.new(flat.X, itemPos.Y + 3, flat.Z)
			local hit = Workspace:Raycast(origin, Vector3.new(0, -60, 0), params)
			if hit and hit.Material ~= Enum.Material.Water and math.abs(hit.Position.Y - itemPos.Y) <= 30 then
				local ground = hit.Position
				if not (find.avoidHazard and nearHazard(ground, CONFIG.HazardTargetMargin)) then
					local safe = resolveSafeCFrame(CFrame.new(ground + Vector3.new(0, 3, 0)), character, root)
					if safe then
						return safe.Position
					end
				end
			end
		end
	end
	return nil
end

-- Teleport ke sebuah titik (menghadap ke arah item).
local function teleportToPoint(point, ctx, cancelled, faceTo)
	local humanoid, root = ctx.humanoid, ctx.root
	if humanoid.SeatPart then
		humanoid.Sit = false
		RunService.Heartbeat:Wait()
	end
	if cancelled() then
		return false
	end
	local look = faceTo and flatten(faceTo - point) or Vector3.zero
	local target
	if look.Magnitude > 0.1 then
		target = CFrame.lookAt(point, point + look)
	else
		target = CFrame.new(point) * (root.CFrame - root.CFrame.Position)
	end
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	RunService.Heartbeat:Wait()
	if cancelled() then
		return false
	end
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

-- Bolak-balik melewati item (depan-belakang lalu kiri-kanan) supaya tersentuh/terambil.
-- Mengembalikan false bila dibatalkan.
local function sweepAround(entry, ctx, cancelled, duration)
	local find = state.find
	local humanoid, root = ctx.humanoid, ctx.root
	local position = entryPosition(entry)
	if not position then
		return true
	end
	local axis = flatten(root.Position - position)
	if axis.Magnitude < 0.5 then
		axis = flatten(root.CFrame.LookVector)
	end
	if axis.Magnitude < 0.01 then
		axis = Vector3.new(0, 0, 1)
	end
	axis = axis.Unit
	local perpendicular = Vector3.new(-axis.Z, 0, axis.X)
	local offsets = { -axis * 3, axis * 3, -perpendicular * 3, perpendicular * 3 }
	local index = 0
	local deadline = os.clock() + duration

	while os.clock() < deadline and entryAlive(entry) do
		index = index % #offsets + 1
		local legEnd = os.clock() + 0.7
		while os.clock() < legEnd and entryAlive(entry) do
			if cancelled() then
				return false
			end
			local itemPos = entryPosition(entry)
			if not itemPos then
				return true
			end
			local waypoint = itemPos + offsets[index]
			if isSwimming(humanoid) and not find.avoidWater then
				swimStep(ctx, Vector3.new(waypoint.X, itemPos.Y, waypoint.Z))
				RunService.Heartbeat:Wait()
			else
				humanoid:MoveTo(Vector3.new(waypoint.X, root.Position.Y, waypoint.Z))
				if itemPos.Y - root.Position.Y > 1.5 and shouldJumpFor(entry) then
					ctxJump(ctx)
				end
				task.wait(0.1)
			end
		end
	end
	return true
end

-- Satu percobaan mendekati target.
-- Status: "collected" | "visited" | "gone" | "cancelled" | "stuck" (+alasan) | "far" (+alasan)
local function approachOnce(entry, ctx, cancelled, timeout)
	local find = state.find
	local character, humanoid, root = ctx.character, ctx.humanoid, ctx.root

	if not entryAlive(entry) then
		return "gone"
	end
	local targetPos = entryPosition(entry)
	if not targetPos then
		return "gone"
	end

	local safeOnly = find.avoidWater or find.avoidHazard
	local routeOptions = {
		avoidWater = find.avoidWater,
		validate = find.avoidHazard and function(waypoints)
			return not waypointsHitHazard(waypoints)
		end or nil,
	}
	local waterTarget = pointInWater(targetPos)

	local startTime = os.clock()
	local anchorPos = root.Position
	local anchorTime = startTime
	local progressTime = startTime
	local bestDist = flatten(targetPos - root.Position).Magnitude
	local metricIn3D = false
	local waypoints = nil
	local wpIndex, lastWpIndex, jumpedIndex = 2, 2, 0
	local lastRepath = -math.huge
	local forceRepath = false
	local pathFails = 0
	local radiusBoost = 0
	local freeRoam = false
	local swimSince = nil

	-- Fase 1: menuju target lewat rute (loncat / berenang), sampai dekat.
	while true do
		if cancelled() then
			return "cancelled"
		end
		if not entryAlive(entry) then
			return (root.Position - targetPos).Magnitude <= 8 and "collected" or "gone"
		end
		targetPos = entryPosition(entry)
		if not targetPos then
			return "gone"
		end

		local now = os.clock()
		local pos = root.Position
		local toTarget = targetPos - pos
		local flatDist = flatten(toTarget).Magnitude
		local swimmingNow = isSwimming(humanoid)
		local swimTo = swimmingNow and not find.avoidWater -- berenang ke item
		local retreat = swimmingNow and find.avoidWater -- keluar dari air

		-- Coin/Gold yang berada di atas karakter: lompat saat sudah cukup dekat.
		if find.jumpHighCoinGold
			and not swimmingNow
			and isCoinOrGoldEntry(entry)
			and targetPos.Y - pos.Y >= CONFIG.FindHighItemJumpHeight
			and flatDist <= CONFIG.FindHighItemJumpDistance then
			ctxJump(ctx)
		end

		local arrived
		if swimTo or waterTarget then
			arrived = toTarget.Magnitude <= CONFIG.FindArriveDistance
		else
			arrived = flatDist <= CONFIG.FindArriveDistance and math.abs(toTarget.Y) <= 6
		end
		if arrived then
			break
		end

		-- Duduk di tengah jalan? Meloncat keluar.
		if isSeated(humanoid) then
			leaveSeat(humanoid, cancelled)
			if cancelled() then
				return "cancelled"
			end
			anchorPos = root.Position
			anchorTime = os.clock()
			continue
		end

		-- Masuk air saat "Hindari Air" aktif: kembali ke titik aman terakhir.
		if retreat then
			swimSince = swimSince or now
		else
			swimSince = nil
			local floor = humanoid.FloorMaterial
			if not swimmingNow and floor ~= Enum.Material.Air and floor ~= Enum.Material.Water then
				ctx.lastSafe = pos
			end
		end

		-- Deteksi tidak bergeser (frozen) dan kemajuan nyata (progress). Saat berenang, jarak 3D yang dihitung.
		if (pos - anchorPos).Magnitude >= 1 then
			anchorPos = pos
			anchorTime = now
		end
		local metric = swimTo and toTarget.Magnitude or flatDist
		if swimTo ~= metricIn3D then
			metricIn3D = swimTo
			bestDist = metric
			progressTime = now
		end
		if metric < bestDist - 2 or wpIndex > lastWpIndex then
			bestDist = math.min(bestDist, metric)
			lastWpIndex = wpIndex
			progressTime = now
		end
		local frozen = now - anchorTime
		local noProgress = now - progressTime
		local elapsed = now - startTime

		local why = nil
		if frozen >= CONFIG.FindStuckTime then
			why = "tersangkut"
		elseif swimSince and now - swimSince >= 3 then
			why = "terjebak di air"
		elseif noProgress >= CONFIG.FindNoProgressTime then
			why = "tidak bisa maju"
		elseif elapsed >= (timeout or CONFIG.FindTargetTimeout) then
			why = "waktu habis"
		elseif pathFails >= 2 and safeOnly and not waypoints and not waterTarget then
			why = "rute aman tidak ada"
		end
		if why then
			humanoid:MoveTo(root.Position)
			return "stuck", why
		end

		if frozen >= 1 and not swimTo then
			ctxJump(ctx)
		end

		-- Hitung / hitung ulang rute (tidak dibutuhkan saat berenang langsung ke item).
		if not freeRoam and not swimTo and (forceRepath or now - lastRepath >= (waypoints and 6 or 0.6)) then
			lastRepath = now
			forceRepath = false
			local newWaypoints = computeWaypoints(root, humanoid, pathGoal(character, entry, targetPos), radiusBoost, routeOptions)
			if newWaypoints then
				waypoints = newWaypoints
				wpIndex, lastWpIndex, jumpedIndex = 2, 2, 0
				pathFails = 0
			elseif not waypoints then
				pathFails += 1
				radiusBoost = (radiusBoost + 1) % 3
				-- Tanpa toggle keamanan (atau target di air), boleh jalan/berenang lurus.
				if pathFails >= 2 and (not safeOnly or waterTarget) then
					freeRoam = true
				end
			end
			anchorTime = os.clock() -- waktu menghitung rute bukan "tersangkut"
			continue
		end

		-- Tentukan titik tujuan langkah ini.
		local moveTarget = nil
		if retreat then
			moveTarget = ctx.lastSafe
			humanoid.Jump = true
		elseif waypoints then
			while waypoints[wpIndex]
				and flatten(waypoints[wpIndex].Position - pos).Magnitude < 3
				and math.abs(waypoints[wpIndex].Position.Y - pos.Y) < 7 do
				wpIndex += 1
			end
			local waypoint = waypoints[wpIndex]
			if waypoint then
				moveTarget = waypoint.Position
				if waypoint.Action == Enum.PathWaypointAction.Jump and jumpedIndex ~= wpIndex then
					jumpedIndex = wpIndex
					ctxJump(ctx)
				end
				-- Terdorong jauh dari rute: hitung ulang.
				if flatten(moveTarget - pos).Magnitude > 16 and now - lastRepath >= 2 then
					forceRepath = true
				end
			else
				moveTarget = targetPos
			end
		elseif freeRoam then
			moveTarget = targetPos
		end

		if swimTo then
			-- Item di air: berenang lurus ke item (naik/turun). Item di darat: ikuti titik rute.
			swimStep(ctx, (waterTarget and targetPos) or moveTarget or targetPos)
			RunService.Heartbeat:Wait()
			continue
		end

		-- Penghalang rendah di depan: loncat.
		if moveTarget then
			local direction = flatten(moveTarget - pos)
			if direction.Magnitude > 0.1 then
				local low, high = checkObstacle(character, root, direction.Unit)
				if low and not high then
					ctxJump(ctx)
				end
			end
			humanoid:MoveTo(moveTarget)
		end
		task.wait(0.1)
	end

	-- Fase 2: pendekatan akhir sampai menyentuh item (melompat / berenang bila perlu).
	local finalDeadline = os.clock() + CONFIG.FindFinalTime + ((waterTarget or isSwimming(humanoid)) and 3 or 0)
	while os.clock() < finalDeadline do
		if cancelled() then
			return "cancelled"
		end
		if not entryAlive(entry) then
			break
		end
		local position = entryPosition(entry)
		if not position then
			break
		end
		if (root.Position - position).Magnitude <= 2.5 then
			break
		end
		if isSwimming(humanoid) and not find.avoidWater then
			swimStep(ctx, position)
			RunService.Heartbeat:Wait()
		else
			humanoid:MoveTo(position)
			if position.Y - root.Position.Y > 2 and shouldJumpFor(entry) then
				ctxJump(ctx)
			end
			task.wait(0.1)
		end
	end
	if cancelled() then
		return "cancelled"
	end

	-- Fase 3: sudah dekat tapi item belum terambil -> interaksi, lalu bolak-balik melewati item.
	if entryAlive(entry) then
		local position = entryPosition(entry)
		if position and (root.Position - position).Magnitude <= 8 then
			activateTarget(entry)
			if not sweepAround(entry, ctx, cancelled, CONFIG.FindSweepTime) then
				return "cancelled"
			end
		end
	end
	task.wait(0.2)
	if cancelled() then
		return "cancelled"
	end

	if entryAlive(entry) then
		local position = entryPosition(entry)
		if position and (root.Position - position).Magnitude > 4.5 then
			return "far", "tidak terjangkau"
		end
		activateTarget(entry)
		task.wait(0.25)
	end
	return entryAlive(entry) and "visited" or "collected"
end

-- Berjalan ke satu target.
-- Bila tersangkut / tidak terjangkau: teleport BERJARAK (bukan tepat di item) lalu bergerak lagi, maksimal
-- CONFIG.FindStandoffRetries kali. Teleport langsung ke item hanya cadangan paling akhir.
-- Mengembalikan: status ("collected" | "visited" | "gone" | "cancelled"), teleported, alasan.
local function findWalkTo(entry, ctx, cancelled)
	local find = state.find
	local teleported, lastReason = false, nil
	local retries = 0
	local timeout = CONFIG.FindTargetTimeout

	while true do
		local status, why = approachOnce(entry, ctx, cancelled, timeout)
		if status ~= "stuck" and status ~= "far" then
			return status, teleported, lastReason
		end
		if cancelled() then
			return "cancelled", teleported, lastReason
		end
		local targetPos = entryPosition(entry)
		if not targetPos or not entryAlive(entry) then
			return "gone", teleported, lastReason
		end

		retries += 1
		if retries <= CONFIG.FindStandoffRetries then
			local distance = math.max(CONFIG.FindStandoffMin, find.standoff * (0.6 ^ retries))
			local point = pickStandoff(entry, ctx, distance)
			if point and teleportToPoint(point, ctx, cancelled, targetPos) then
				teleported, lastReason = true, why
				timeout = CONFIG.FindRetryTimeout
				task.wait(0.3)
				continue
			end
			if cancelled() then
				return "cancelled", teleported, lastReason
			end
		end

		-- Cadangan terakhir: semua percobaan berjarak gagal.
		if not teleportToTarget(entry, ctx, cancelled) then
			return cancelled() and "cancelled" or "gone", teleported, lastReason
		end
		task.wait(0.5)
		if cancelled() then
			return "cancelled", true, why
		end
		activateTarget(entry)
		task.wait(0.2)
		return entryAlive(entry) and "visited" or "collected", true, tostring(why) .. ", teleport langsung"
	end
end

-- Mode Teleport: lompat ke titik berjarak dari item, lalu bergerak/berenang/loncat ke item seperti mode jalan.
local function teleportApproach(entry, ctx, cancelled)
	local find = state.find
	if not entryAlive(entry) then
		return "gone", false
	end
	local targetPos = entryPosition(entry)
	if not targetPos then
		return "gone", false
	end
	local teleported = false
	local point = pickStandoff(entry, ctx, find.standoff)
		or pickStandoff(entry, ctx, math.max(CONFIG.FindStandoffMin, find.standoff * 0.5))
	if point and teleportToPoint(point, ctx, cancelled, targetPos) then
		teleported = true
		task.wait(0.35) -- biarkan karakter mendarat / mulai berenang sebelum bergerak
	elseif cancelled() then
		return "cancelled", false
	end
	local status, walkTeleported, reason = findWalkTo(entry, ctx, cancelled)
	if teleported and not reason then
		reason = string.format("mode teleport, jarak %d stud", find.standoff)
	end
	return status, teleported or walkTeleported, reason
end

-- Rejoin server setelah sejumlah Coin berturut-turut gagal dikoleksi.
local rejoinRequested = false
local function requestServerRejoin(reason)
	if rejoinRequested or state.closed then
		return false
	end
	rejoinRequested = true
	state.find.token += 1
	state.moveToken += 1
	state.find.running = false
	state.find.scanning = false
	state.busy = false
	restoreWalkSpeed()
	persistSavedData()
	if state.advanced.autoExecuteEnabled then
		local queued, queueMessage = queueAutoExecute(true)
		if not queued then
			notify("Autoexecute belum bisa disiapkan: " .. tostring(queueMessage), "warning")
		end
	end
	notify(reason or "Mencoba rejoin server...", "warning")

	local ok, err = pcall(function()
		TeleportService:Teleport(game.PlaceId, player)
	end)
	if not ok then
		-- Beberapa executor membungkus signature Teleport secara berbeda.
		ok, err = pcall(function()
			TeleportService:Teleport(game.PlaceId)
		end)
	end
	if not ok then
		rejoinRequested = false
		notify("Rejoin gagal dimulai: " .. tostring(err), "error")
		return false
	end
	return true
end

-- Satu sesi Find: scan -> hitung -> saring (air/bahaya) -> jalan berurutan dari yang terdekat.
local function runFindSession(token, scanOnly)
	local find = state.find

	find.statusText = "Memindai peta..."
	refreshFindUI()
	local scan = scanTargets(token)
	if not scan then
		find.statusText = "Scan dibatalkan."
		refreshFindUI()
		return
	end
	if state.closed or find.token ~= token then
		return
	end
	applyScan(scan)
	refreshResultList()
	rebuildESP()

	local total = #find.results
	local counts = describeCounts()
	if total == 0 then
		local rawTotal = #find.raw
		if rawTotal > 0 then
			find.statusText = string.format("%d objek cocok nama, tapi tidak lolos filter tipe (cek chip Jenis / Pemicu).", rawTotal)
		elseif find.loopEnabled and not scanOnly then
			find.statusText = "Loop Find: belum ada target; akan scan ulang."
		else
			find.statusText = "Tidak ada target ditemukan."
		end
		refreshFindUI()
		if not (find.loopEnabled and not scanOnly) then
			if rawTotal > 0 then
				notify(string.format("%d objek cocok nama tapi bukan item yang bisa diambil. Aktifkan \"Tanpa pemicu\" bila perlu.", rawTotal), "warning")
			else
				notify("Tidak ada target ditemukan. Coba kategori lain atau kata kunci manual.", "warning")
			end
		end
		return
	end
	find.statusText = string.format("Scan: %d target • %s", total, counts)
	refreshFindUI()
	if not find.loopEnabled or scanOnly then
		notify(string.format("Ditemukan %d target: %s.", total, counts), "success")
	end
	if find.truncated and (not find.loopEnabled or scanOnly) then
		notify(string.format("Hasil mentah dibatasi %d objek pertama.", CONFIG.FindMaxRaw), "info")
	end
	if scanOnly then
		return
	end

	if state.busy then
		notify("Perjalanan Return sedang berjalan. Tekan Stop dulu, lalu mulai Find.", "warning")
		return
	end
	task.wait(1) -- beri waktu membaca jumlah target sebelum mulai berjalan
	if state.closed or find.token ~= token then
		return
	end

	local character, humanoid, root = waitForCharacter(8)
	if not root then
		notify("Karakter belum siap. Find dibatalkan.", "warning")
		return
	end

	-- Saring target sesuai toggle.
	local queue = {}
	local skipped = { water = 0, hazard = 0, gone = 0 }
	for index, entry in ipairs(find.results) do
		if index % 20 == 0 then
			task.wait()
			if state.closed or find.token ~= token then
				return
			end
		end
		local reason = entryUnsafeReason(entry, character)
		if reason then
			skipped[reason] += 1
		else
			table.insert(queue, entry)
		end
	end
	local skippedTotal = skipped.water + skipped.hazard + skipped.gone
	if #queue == 0 then
		find.statusText = find.loopEnabled and "Loop Find: tidak ada target aman; scan ulang." or "Semua target dilewati (air/bahaya)."
		refreshFindUI()
		if not find.loopEnabled then
			notify("Semua target dilewati karena berada di air/dekat bahaya.", "warning")
		end
		return
	end
	if skippedTotal > 0 and not find.loopEnabled then
		notify(string.format("Dilewati %d target (air %d, bahaya %d, hilang %d). Berjalan ke %d target.", skippedTotal, skipped.water, skipped.hazard, skipped.gone, #queue), "info")
	end

	-- Scan/filter selesai; tidak ada jeda tanpa tombol Stop sebelum mulai berjalan.
	find.scanning = false
	-- Mulai berjalan.
	find.running = true
	state.busy = true
	state.moveToken += 1
	local moveToken = state.moveToken
	find.total = #queue
	find.done, find.collected, find.visited, find.gone, find.teleports = 0, 0, 0, 0, 0
	refreshUI()

	local function cancelled()
		return state.closed or find.token ~= token or moveToken ~= state.moveToken
			or player.Character ~= character or not root.Parent or humanoid.Health <= 0
	end

	if isSeated(humanoid) then
		setStatus("Karakter sedang duduk, meloncat keluar dari kursi...", "info")
		leaveSeat(humanoid, cancelled)
	end
	applyWalkSpeed(humanoid, find.speedPct)

	local ctx = { character = character, humanoid = humanoid, root = root, lastSafe = root.Position }
	local order = 0
	local interrupted = false

	while #queue > 0 do
		if cancelled() then
			interrupted = true
			break
		end

		-- Urutan: target terdekat dari posisi sekarang.
		local pos = root.Position
		local bestIndex, bestDist = 1, math.huge
		for index, entry in ipairs(queue) do
			local position = entryPosition(entry)
			if position then
				local distance = (position - pos).Magnitude
				if distance < bestDist then
					bestIndex, bestDist = index, distance
				end
			end
		end
		local entry = table.remove(queue, bestIndex)
		order += 1
		find.statusText = string.format("Berjalan %d/%d: %s \"%s\"", order, find.total, entry.label, entry.name)
		setStatus(find.statusText, "info")
		refreshFindUI()

		local targetDeadline = os.clock() + CONFIG.FindCollectTimeout
		local status, teleported, reason
		if find.mode == "teleport" then
			status, teleported, reason = teleportApproach(entry, ctx, cancelled)
		else
			status, teleported, reason = findWalkTo(entry, ctx, cancelled)
		end
		if status == "cancelled" or cancelled() then
			interrupted = true
			break
		end

		-- Jangan langsung skip hanya karena karakter sudah sampai. Beri waktu maksimal
		-- 15 detik untuk item benar-benar hilang/terambil, sambil mencoba interaksi ulang.
		local collectDeadline = targetDeadline
		while status ~= "gone" and entryAlive(entry) and os.clock() < collectDeadline do
			if cancelled() then
				interrupted = true
				break
			end
			activateTarget(entry)
			local targetPos = entryPosition(entry)
			if targetPos and (root.Position - targetPos).Magnitude > 5 then
				-- Terdorong menjauh: dekati lagi (loncat / berenang tetap berlaku).
				local retryStatus = findWalkTo(entry, ctx, cancelled)
				if retryStatus == "cancelled" then
					interrupted = true
					break
				end
			else
				-- Dekat tapi belum terambil: bolak-balik melewati item.
				if not sweepAround(entry, ctx, cancelled, 1.5) then
					interrupted = true
					break
				end
			end
			task.wait(0.2)
		end
		if interrupted then break end
		if not entryAlive(entry) then
			status = "collected"
		elseif status ~= "gone" then
			-- Limit tercapai: baru sekarang target dianggap gagal dan dilewati.
			status = "visited"
			find.statusText = string.format("Timeout 15 dtk: \"%s\" belum terambil, lanjut target berikutnya.", entry.name)
			setStatus(find.statusText, "warning")
		end

		find.done += 1
		if status == "collected" then
			find.collected += 1
		elseif status == "visited" then
			find.visited += 1
		else
			find.gone += 1
		end

		-- Hanya Coin yang masih ada tetapi gagal dikoleksi (status "visited") dihitung.
		-- Coin berhasil diambil mereset hitungan berturut-turut.
		if entry.id == "coin" then
			if status == "collected" then
				find.failedCoinSkips = 0
			elseif status == "visited" then
				find.failedCoinSkips += 1
				if find.failedCoinSkips >= CONFIG.FindFailedCoinRejoinLimit then
					find.statusText = string.format("%d Coin berturut-turut gagal diambil; mencoba rejoin server...", CONFIG.FindFailedCoinRejoinLimit)
					refreshFindUI()
					requestServerRejoin(find.statusText)
					return
				end
			end
		end

		if teleported then
			find.teleports += 1
			notify(string.format("Teleport berjarak ke dekat \"%s\" (%s).", entry.name, reason or "mode teleport"), "warning")
		end
		refreshFindUI()
	end

	local summary = string.format(
		"%d/%d diproses • diambil %d • disentuh %d • hilang %d • teleport %d",
		find.done, find.total, find.collected, find.visited, find.gone, find.teleports
	)
	if interrupted then
		find.statusText = "Find berhenti: " .. summary
		if not state.closed then
			notify("Find berhenti: " .. summary .. ".", "info")
		end
	elseif find.loopEnabled then
		find.statusText = "Loop Find: ronde selesai (" .. summary .. "); scan ulang sebentar lagi."
	else
		find.statusText = "Find selesai: " .. summary
		notify("Find selesai: " .. summary .. ".", "success")
	end

	-- Daftar hasil tetap ditampilkan (item yang sudah terambil otomatis hilang dari daftar / ESP).
	find.hazards = {}
	refreshResultList()
	rebuildESP()
end

stopFind = function()
	local find = state.find
	if state.closed or not (find.running or find.scanning) then
		return
	end
	find.token += 1
	if find.running then
		state.moveToken += 1
		state.autoPauseUntil = os.clock() + math.max(state.autoDelay, 3)
	end
	notify("Find dihentikan.", "info")
end

startFind = function(scanOnly)
	local find = state.find
	if state.closed or find.running or find.scanning then
		return
	end
	if not scanOnly and state.busy then
		notify("Perjalanan Return sedang berjalan. Tekan Stop dulu, lalu mulai Find.", "warning")
		return
	end

	if ui.findBox then
		find.custom = sanitizeKeywords(ui.findBox.Text)
	end
	if #buildMatchers() == 0 then
		notify("Pilih minimal satu kategori atau isi kata kunci manual.", "warning")
		return
	end
	persistSavedData()

	find.token += 1
	local token = find.token
	if not scanOnly then
		find.failedCoinSkips = 0
	end
	find.scanning = true
	refreshUI()

	spawnTask(function()
		while not state.closed and find.token == token do
			local ok, err = pcall(runFindSession, token, scanOnly)
			local wasRunning = find.running
			find.scanning = false
			find.running = false
			if wasRunning then
				restoreWalkSpeed()
				state.busy = false
				state.autoPauseUntil = os.clock() + 2
			end
			if state.closed then
				return
			end
			if not ok then
				warn("[IsekaiReturnSystem] Find error: " .. tostring(err))
				find.statusText = "Find gagal karena error internal."
				notify("Find gagal karena error internal.", "error")
				break
			end
			refreshUI()
			if scanOnly or not find.loopEnabled or find.token ~= token then
				break
			end

			-- Selama jeda loop, Find tetap berstatus aktif agar tombol Stop dapat membatalkan.
			find.scanning = true
			find.statusText = "Loop Find: scan berikutnya dalam " .. string.format("%.1f", CONFIG.FindLoopDelay) .. " dtk..."
			refreshUI()
			task.wait(CONFIG.FindLoopDelay)
			if state.closed or find.token ~= token or not find.loopEnabled then
				break
			end
		end

		find.scanning = false
		find.running = false
		if not state.closed then
			refreshUI()
		end
	end)
end

--------------------------------------------------------------------------------
-- ANTI-AFK
--------------------------------------------------------------------------------

local function stopAntiAFK(message, kind)
	if not state.afk.active then
		return
	end
	state.afk.active = false
	state.afk.token += 1
	if ui.afkCountdown then
		ui.afkCountdown.Text = "Tekan berikutnya: --:--"
	end
	persistSavedData()
	refreshUI()
	notify(message or "Anti-AFK dimatikan.", kind or "info")
end

local function runAfkTimer(token)
	while not state.closed and state.afk.active and state.afk.token == token do
		local remaining = state.afk.endsAt - os.clock()
		if remaining <= 0 then
			-- Interval habis: tekan keybind lalu ulangi sampai Anti-AFK dimatikan.
			state.afk.endsAt = os.clock() + state.afk.minutes * 60
			local keyName = state.afk.keyCode.Name
			if pressKey(state.afk.keyCode) then
				notify(string.format("Anti-AFK: tombol %s ditekan. Berikutnya %d menit lagi.", keyName, state.afk.minutes), "info")
			else
				notify("Anti-AFK gagal menekan tombol (input virtual tidak tersedia).", "warning")
			end
		else
			if ui.afkCountdown then
				ui.afkCountdown.Text = "Tekan berikutnya: " .. formatTime(remaining)
			end
			refreshStatus()
		end
		task.wait(0.5)
	end
end

local function startAntiAFK(minutes)
	state.afk.minutes = minutes
	state.afk.active = true
	state.afk.token += 1
	state.afk.endsAt = os.clock() + minutes * 60
	local token = state.afk.token
	persistSavedData()
	refreshUI()
	spawnTask(runAfkTimer, token)
end

local function applyDuration(showSuccess)
	local minutes, reason = validateDuration(ui.durationBox and ui.durationBox.Text or "")
	if not minutes then
		if ui.durationStroke then
			ui.durationStroke.Color = THEME.Error
		end
		notify(reason, "warning")
		return nil
	end
	if ui.durationStroke then
		ui.durationStroke.Color = THEME.Border
	end
	state.afk.minutes = minutes
	persistSavedData()
	if state.afk.active then
		state.afk.endsAt = os.clock() + minutes * 60
	end
	refreshUI()
	if showSuccess then
		notify(string.format("Interval Anti-AFK diset ke %d menit.", minutes), "success")
	end
	return minutes
end

pressKey = function(keyCode)
	local focused = UserInputService:GetFocusedTextBox()
	if focused then
		focused:ReleaseFocus()
	end
	local sent = pcall(function()
		local vim = game:GetService("VirtualInputManager")
		vim:SendKeyEvent(true, keyCode, false, game)
		task.wait(0.12)
		vim:SendKeyEvent(false, keyCode, false, game)
	end)
	if sent then
		return true
	end
	if keyCode == Enum.KeyCode.Space then
		local _, humanoid = getCharacterParts()
		if humanoid then
			humanoid.Jump = true
			return true
		end
	end
	return false
end

toggleAntiAFK = function()
	if state.closed then
		return
	end
	if state.afk.active then
		stopAntiAFK("Anti-AFK dimatikan.", "info")
		return
	end
	local minutes = applyDuration(false)
	if not minutes then
		return
	end
	startAntiAFK(minutes)
	notify(string.format("Anti-AFK aktif: menekan %s tiap %d menit.", state.afk.keyCode.Name, minutes), "success")
	spawnTask(function()
		task.wait(0.4)
		if state.closed or not state.afk.active then
			return
		end
		local keyName = state.afk.keyCode.Name
		if pressKey(state.afk.keyCode) then
			notify(string.format("Tes: tombol %s ditekan. Lihat apakah karakter bereaksi.", keyName), "info")
		else
			notify("Tombol tidak bisa ditekan otomatis di lingkungan ini (input virtual tidak tersedia).", "warning")
		end
	end)
end

local function onIdled()
	if state.closed or not state.afk.active then
		return
	end
	local ok = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
	if not ok and not state.afk.vuWarned then
		state.afk.vuWarned = true
		notify("Anti-AFK gagal mengirim input virtual di lingkungan ini.", "error")
	end
end

local function beginKeyCapture()
	if state.closed then
		return
	end
	state.capturingFindKey = nil
	state.capturingKey = true
	refreshUI()
	notify("Tekan tombol keyboard untuk keybind baru (Esc untuk batal).", "info")
end

local BLOCKED_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.Unknown] = true,
}

local MOVE_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
}

local function onInputBegan(input, processed)
	if state.closed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end

	if state.capturingFindKey then
		local categoryId = state.capturingFindKey
		state.capturingFindKey = nil
		if input.KeyCode == Enum.KeyCode.Escape then
			refreshFindUI()
			notify("Pengaturan keybind kategori dibatalkan.", "info")
			return
		end
		if BLOCKED_KEYS[input.KeyCode] then
			refreshFindUI()
			notify("Tombol itu dipakai untuk kontrol gerak. Pilih tombol lain, misalnya E atau F.", "warning")
			return
		end
		state.find.interactKeys[categoryId] = input.KeyCode
		persistSavedData()
		refreshFindUI()
		local label = categoryId
		for _, category in ipairs(FIND_CATEGORIES) do
			if category.id == categoryId then
				label = category.label
				break
			end
		end
		notify(string.format("Keybind interaksi %s diset ke %s.", label, input.KeyCode.Name), "success")
		return
	end

	if state.capturingKey then
		state.capturingKey = false
		if input.KeyCode == Enum.KeyCode.Escape then
			refreshUI()
			notify("Pengaturan keybind dibatalkan.", "info")
			return
		end
		if BLOCKED_KEYS[input.KeyCode] then
			refreshUI()
			notify("Tombol itu dipakai untuk kontrol game. Pilih tombol lain.", "warning")
			return
		end
		state.afk.keyCode = input.KeyCode
		persistSavedData()
		refreshUI()
		notify(string.format("Keybind Anti-AFK diset ke %s.", input.KeyCode.Name), "success")
		return
	end

	if processed then
		return
	end
	if MOVE_KEYS[input.KeyCode] and (state.find.running or state.find.scanning) then
		stopFind()
		return
	end
	if state.busy and MOVE_KEYS[input.KeyCode] then
		cancelMove()
	end
end

--------------------------------------------------------------------------------
-- TOAST NOTIFICATIONS
--------------------------------------------------------------------------------

local pumpToasts

local function runToast(item)
	local color = KIND_COLOR[item.kind] or THEME.Info
	local glyph = KIND_GLYPH[item.kind] or "i"
	toastCounter += 1

	local wrapper = new("Frame", {
		Parent = ui.toastHolder,
		Size = UDim2.new(1, 0, 0, CONFIG.ToastHeight),
		BackgroundTransparency = 1,
		LayoutOrder = toastCounter,
	})
	local card = new("CanvasGroup", {
		Parent = wrapper,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.new(0, 0, -1.4, 0),
		BackgroundColor3 = Color3.fromRGB(20, 14, 33),
		BackgroundTransparency = 0.04,
		GroupTransparency = 1,
	}, {
		corner(16),
		stroke(color, 1.2, 0.35),
		padding(12, 8, 14, 8),
	})
	local icon = new("Frame", {
		Parent = card,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(0, 0, 0.5, -15),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.78,
	}, { corner(15) })
	new("TextLabel", {
		Parent = icon,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = glyph,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = color,
	})
	new("TextLabel", {
		Parent = card,
		Position = UDim2.new(0, 42, 0, 0),
		Size = UDim2.new(1, -42, 1, 0),
		BackgroundTransparency = 1,
		Text = item.message,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})

	tween(card, 0.35, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 }, Enum.EasingStyle.Quint)
	task.wait(0.35 + item.duration)
	if state.closed then
		return
	end
	tween(card, 0.3, { Position = UDim2.new(0, 0, -1.4, 0), GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.3)
	if state.closed then
		return
	end
	tween(wrapper, 0.12, { Size = UDim2.new(1, 0, 0, 0) })
	task.wait(0.12)
	if state.closed then
		return
	end
	wrapper:Destroy()
	toastMessages[item.message] = nil
	toastActive -= 1
	pumpToasts()
end

pumpToasts = function()
	while not state.closed and toastActive < CONFIG.MaxToasts and #toastQueue > 0 do
		local item = table.remove(toastQueue, 1)
		toastActive += 1
		spawnTask(runToast, item)
	end
end

showNotification = function(message, kind, duration)
	if state.closed or not ui.toastHolder or not ui.toastHolder.Parent then
		return
	end
	if toastMessages[message] then
		return
	end
	toastMessages[message] = true
	if #toastQueue >= 8 then
		local dropped = table.remove(toastQueue, 1)
		toastMessages[dropped.message] = nil
	end
	table.insert(toastQueue, {
		message = message,
		kind = kind or "info",
		duration = duration or CONFIG.ToastDuration,
	})
	pumpToasts()
end

--------------------------------------------------------------------------------
-- UI BUILDERS
--------------------------------------------------------------------------------

local function makeLabel(parent, text, size, color, bold)
	return new("TextLabel", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 2),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextSize = size,
		TextColor3 = color or THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	})
end

local function makeButton(parent, text, color, size)
	return new("TextButton", {
		Parent = parent,
		Size = size or UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.04,
		AutoButtonColor = true,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = THEME.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, {
		corner(10),
		stroke(Color3.new(1, 1, 1), 1, 0.85),
	})
end

local function makeTextBox(parent, placeholder, size)
	local box = new("TextBox", {
		Parent = parent,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(16, 11, 27),
		BackgroundTransparency = 0.05,
		Text = "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = THEME.Muted,
		TextColor3 = THEME.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, {
		corner(10),
		padding(10, 0, 10, 0),
	})
	local boxStroke = stroke(THEME.Border, 1, 0.3)
	boxStroke.Parent = box
	return box, boxStroke
end

local function makeCard(parent, order)
	return new("Frame", {
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Surface,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
	}, {
		corner(14),
		stroke(THEME.Border, 1, 0.5),
		padding(12, 12, 12, 12),
		new("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function makeSectionHeader(parent, title, order)
	local header = new("Frame", {
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	})
	new("TextLabel", {
		Parent = header,
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = THEME.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local right = new("TextLabel", {
		Parent = header,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 70, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	return right
end

local function makeRow(parent, order, height)
	return new("Frame", {
		Parent = parent,
		Size = UDim2.new(1, 0, 0, height or 36),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function clampCenter(center, half, bounds)
	local margin = 60
	local x = math.clamp(center.X, margin - half.X, bounds.X - margin + half.X)
	local y = math.clamp(center.Y, margin - half.Y, bounds.Y - margin + half.Y)
	return Vector2.new(x, y)
end

local function makeDraggable(handle, target)
	local drag = { moved = false }
	local dragging = false
	local dragInput = nil
	local startMouse = Vector2.zero
	local startCenter = Vector2.zero

	connect(handle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragInput = input
			drag.moved = false
			startMouse = Vector2.new(input.Position.X, input.Position.Y)
			startCenter = Vector2.new(target.Position.X.Offset, target.Position.Y.Offset)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - startMouse
			if delta.Magnitude > 6 then
				drag.moved = true
			end
			if drag.moved then
				local half = target.AbsoluteSize / 2
				local center = clampCenter(startCenter + delta, half, ui.gui.AbsoluteSize)
				target.Position = UDim2.fromOffset(center.X, center.Y)
			end
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			dragInput = nil
		end
	end)
	return drag
end

local function makeSlider(parent, order, title, minValue, maxValue, step, initial, formatValue, onChange, onCommit)
	local holder = new("Frame", {
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	})
	local titleLabel = new("TextLabel", {
		Parent = holder,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local hit = new("Frame", {
		Parent = holder,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Active = true,
	})
	local track = new("Frame", {
		Parent = hit,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Color3.fromRGB(20, 14, 34),
	}, { corner(4) })
	local fill = new("Frame", {
		Parent = track,
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.Accent,
	}, { corner(4) })
	local knob = new("Frame", {
		Parent = track,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = THEME.Text,
		ZIndex = 2,
	}, { corner(10), stroke(THEME.Accent, 2, 0) })

	local slider = { value = initial }
	local sliding = false
	local slideInput = nil

	local function render()
		local alpha = (slider.value - minValue) / (maxValue - minValue)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		titleLabel.Text = title .. ": " .. formatValue(slider.value)
	end

	function slider.set(value)
		if sliding then
			return
		end
		slider.value = value
		render()
	end

	local function updateFromX(x)
		local alpha = math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
		local raw = minValue + alpha * (maxValue - minValue)
		local snapped = math.clamp(math.floor(raw / step + 0.5) * step, minValue, maxValue)
		if snapped ~= slider.value then
			slider.value = snapped
			render()
			onChange(snapped)
		end
	end

	connect(hit.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sliding = true
			slideInput = input
			updateFromX(input.Position.X)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input == slideInput) then
			updateFromX(input.Position.X)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if sliding and (input == slideInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
			sliding = false
			slideInput = nil
			onCommit(slider.value)
		end
	end)

	render()
	return slider
end

local function askConfirm(message, confirmText, onConfirm)
	if state.closed or not ui.confirmOverlay then
		return
	end
	ui.confirmMessage.Text = message
	ui.confirmYes.Text = confirmText
	ui.confirmCallback = onConfirm
	ui.confirmOverlay.Visible = true
end

local function hideConfirm()
	ui.confirmCallback = nil
	if ui.confirmOverlay then
		ui.confirmOverlay.Visible = false
	end
end

local function layoutUI()
	if state.closed or not ui.gui then
		return
	end
	local size = ui.gui.AbsoluteSize
	local width = math.clamp(size.X - 24, 280, 390)
	local height = math.clamp(size.Y - 80, 330, 590)
	ui.root.Size = UDim2.fromOffset(width, height)
	ui.toastHolder.Size = UDim2.fromOffset(math.clamp(size.X - 24, 240, 380), 0)

	local rootCenter = clampCenter(
		Vector2.new(ui.root.Position.X.Offset, ui.root.Position.Y.Offset),
		Vector2.new(width / 2, height / 2),
		size
	)
	ui.root.Position = UDim2.fromOffset(rootCenter.X, rootCenter.Y)

	local pillCenter = clampCenter(
		Vector2.new(ui.pill.Position.X.Offset, ui.pill.Position.Y.Offset),
		Vector2.new(46, 17),
		size
	)
	ui.pill.Position = UDim2.fromOffset(pillCenter.X, pillCenter.Y)
end

local function setMinimized(minimized)
	if state.closed or not state.uiReady then
		return
	end
	state.minimized = minimized
	state.visToken += 1
	local token = state.visToken
	if minimized then
		tween(ui.panel, 0.2, { GroupTransparency = 1 })
		tween(ui.rootScale, 0.2, { Scale = 0.94 })
		spawnTask(function()
			task.wait(0.2)
			if state.closed or token ~= state.visToken then
				return
			end
			ui.root.Visible = false
			ui.pill.Visible = true
		end)
	else
		ui.pill.Visible = false
		ui.rootScale.Scale = 0.94
		ui.panel.GroupTransparency = 1
		ui.root.Visible = true
		tween(ui.panel, 0.25, { GroupTransparency = 0 })
		tween(ui.rootScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local function resolveGuiParent(gui)
	if type(gethui) == "function" then
		local ok, container = pcall(gethui)
		if ok and typeof(container) == "Instance" then
			local assigned = pcall(function()
				gui.Parent = container
			end)
			if assigned and gui.Parent == container then
				return
			end
		end
	end
	local assigned = pcall(function()
		gui.Parent = game:GetService("CoreGui")
	end)
	if assigned and gui.Parent then
		return
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

--------------------------------------------------------------------------------
-- ESP + DAFTAR HASIL FIND
--------------------------------------------------------------------------------

local esp = { gui = nil, items = {}, token = 0, nextScan = 0 }

local function destroyEspItems()
	for entry, item in pairs(esp.items) do
		esp.items[entry] = nil
		item.board:Destroy()
	end
end

local function ensureEspGui()
	if esp.gui and esp.gui.Parent then
		return true
	end
	local gui = new("ScreenGui", {
		Name = "IsekaiReturnSystem_ESP",
		ResetOnSpawn = false,
		DisplayOrder = 900,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	resolveGuiParent(gui)
	esp.gui = gui
	return gui.Parent ~= nil
end

-- Membuat ulang penanda ESP untuk semua hasil yang lolos filter.
rebuildESP = function()
	destroyEspItems()
	if state.closed or not state.find.espEnabled then
		return
	end
	if not ensureEspGui() then
		return
	end
	for _, entry in ipairs(state.find.results) do
		local visual = entry.visual
		if visual and visual.Parent and entryAlive(entry) then
			local color = ESP_COLORS[entry.id] or ESP_COLORS.custom
			local label = new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				Text = entry.name,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = color,
				TextStrokeTransparency = 0.35,
				TextStrokeColor3 = Color3.new(0, 0, 0),
			})
			local board = new("BillboardGui", {
				Name = "ESP",
				Adornee = visual,
				AlwaysOnTop = true,
				Size = UDim2.fromOffset(150, 34),
				StudsOffset = Vector3.new(0, 2, 0),
				LightInfluence = 0,
				ResetOnSpawn = false,
				Parent = esp.gui,
			}, {
				label,
				new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 22),
					Size = UDim2.fromOffset(9, 9),
					BackgroundColor3 = color,
				}, { corner(5), stroke(Color3.new(0, 0, 0), 1, 0.2) }),
			})
			esp.items[entry] = { board = board, label = label }
		end
	end
end

local function updateEspLabels()
	local _, _, root = getCharacterParts()
	for entry, item in pairs(esp.items) do
		if not entryAlive(entry) then
			esp.items[entry] = nil
			item.board:Destroy()
		else
			local position = entryPosition(entry)
			if position and root then
				item.label.Text = string.format("%s • %dm", entry.name, math.floor((position - root.Position).Magnitude))
			end
		end
	end
end

-- Isi ulang daftar hasil (diurutkan dari yang terdekat) + ringkasan jumlah per kategori / jenis / pemicu.
refreshResultList = function()
	if state.closed or not ui.resultList then
		return
	end
	local find = state.find
	for _, child in ipairs(ui.resultList:GetChildren()) do
		if child.Name == "Row" then
			child:Destroy()
		end
	end

	local _, _, root = getCharacterParts()
	local rows = {}
	for _, entry in ipairs(find.results) do
		local position = entryPosition(entry)
		if position and entryAlive(entry) then
			table.insert(rows, {
				entry = entry,
				distance = root and (position - root.Position).Magnitude or 0,
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.distance < b.distance
	end)

	ui.resultEmpty.Visible = #rows == 0
	ui.resultCount.Text = #rows > 0 and string.format("%d item", #rows) or ""

	local shown = math.min(#rows, CONFIG.ResultListMax)
	for index = 1, shown do
		local row, entry = rows[index], rows[index].entry
		new("TextLabel", {
			Name = "Row",
			Parent = ui.resultList,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = string.format("[%s] %s • %s • %d stud", entry.label, entry.name, entry.typeText, math.floor(row.distance)),
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextColor3 = ESP_COLORS[entry.id] or THEME.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	if #rows > shown then
		new("TextLabel", {
			Name = "Row",
			Parent = ui.resultList,
			LayoutOrder = shown + 1,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = string.format("... +%d item lainnya", #rows - shown),
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	if not find.scanned then
		ui.resultSummary.Text = "Belum dipindai. Tekan Scan atau nyalakan ESP."
		return
	end
	local kinds, trigs = find.kindCounts, find.trigCounts
	ui.resultSummary.Text = string.format(
		"Cocok nama: %d • Lolos filter: %d%s\nKategori: %s\nJenis: Part %d • Model %d • Tool %d\nPemicu: Prompt %d • Click %d • Touch %d • Tanpa pemicu %d",
		#find.raw, #find.results, find.truncated and " (dibatasi)" or "",
		describeCounts(),
		kinds.part, kinds.model, kinds.tool,
		trigs.prompt, trigs.click, trigs.touch, trigs.plain
	)
end

-- Loop ESP: memperbarui jarak, membuang item yang sudah terambil, dan memindai ulang berkala.
local function espLoop(token)
	local find = state.find
	while not state.closed and esp.token == token and find.espEnabled do
		if os.clock() >= esp.nextScan and not find.running and not find.scanning then
			esp.nextScan = os.clock() + CONFIG.EspRescanInterval
			local scan = scanTargets(find.token, true)
			if scan and not state.closed and esp.token == token and find.espEnabled
				and not find.running and not find.scanning then
				applyScan(scan)
				find.statusText = string.format("ESP: %d item terlihat (%s)", #find.results, describeCounts())
				rebuildESP()
				refreshResultList()
				refreshFindUI()
			elseif not scan and not state.closed and #buildMatchers() == 0 then
				find.statusText = "ESP: pilih minimal satu kategori atau isi kata kunci manual."
				refreshFindUI()
			end
		end
		updateEspLabels()
		task.wait(0.25)
	end
end

local function setEsp(enabled)
	local find = state.find
	find.espEnabled = enabled
	esp.token += 1
	if enabled then
		if ui.findBox then
			find.custom = sanitizeKeywords(ui.findBox.Text)
		end
		esp.nextScan = 0
		local token = esp.token
		find.statusText = "ESP aktif: memindai item..."
		spawnTask(function()
			espLoop(token)
		end)
	else
		destroyEspItems()
		find.statusText = "ESP dimatikan."
	end
	refreshFindUI()
end

-- Dipanggil saat chip jenis / pemicu diubah: saring ulang tanpa scan ulang.
local function onFilterChanged()
	persistSavedData()
	applyFilters()
	refreshResultList()
	rebuildESP()
	refreshFindUI()
end

-- Kategori / kata kunci berubah: ESP perlu scan ulang segera.
local function onScanCriteriaChanged()
	persistSavedData()
	esp.nextScan = 0
	refreshFindUI()
end

local function buildUI()
	local gui = new("ScreenGui", {
		Name = "IsekaiReturnSystem_UI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	resolveGuiParent(gui)
	ui.gui = gui

	-- Root (draggable container) ------------------------------------------------
	ui.rootScale = new("UIScale", { Scale = 1 })
	ui.root = new("Frame", {
		Parent = gui,
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(gui.AbsoluteSize.X / 2, gui.AbsoluteSize.Y / 2),
		Size = UDim2.fromOffset(360, 520),
		BackgroundTransparency = 1,
		Visible = false,
	}, { ui.rootScale })

	new("Frame", {
		Parent = ui.root,
		Name = "Shadow",
		Position = UDim2.fromOffset(-6, 2),
		Size = UDim2.new(1, 12, 1, 12),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.62,
		ZIndex = 0,
	}, { corner(24) })

	ui.panel = new("CanvasGroup", {
		Parent = ui.root,
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Background,
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ZIndex = 1,
	}, {
		corner(20),
		stroke(THEME.Accent, 1.5, 0.55),
	})
	-- Gradient sengaja di frame terpisah: UIGradient pada CanvasGroup akan menggelapkan SEMUA isinya.
	new("Frame", {
		Parent = ui.panel,
		Name = "Glass",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.02,
		ZIndex = 0,
	}, {
		new("UIGradient", {
			Rotation = 135,
			Color = ColorSequence.new(THEME.BackgroundAlt, THEME.Background),
		}),
	})

	-- Header --------------------------------------------------------------------
	local header = new("Frame", {
		Parent = ui.panel,
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = THEME.SurfaceHi,
		BackgroundTransparency = 0.35,
	})
	new("Frame", {
		Parent = header,
		Position = UDim2.fromOffset(14, 19),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = THEME.Accent,
	}, { corner(4) })
	new("TextLabel", {
		Parent = header,
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -112, 1, 0),
		BackgroundTransparency = 1,
		Text = CONFIG.Title,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = THEME.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	new("Frame", {
		Parent = header,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = THEME.Accent,
		BackgroundTransparency = 0.7,
	})
	local controls = new("Frame", {
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(64, 28),
		BackgroundTransparency = 1,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.minimizeBtn = makeButton(controls, "−", THEME.SurfaceHi, UDim2.fromOffset(28, 28))
	ui.minimizeBtn.TextSize = 18
	ui.minimizeBtn.LayoutOrder = 1
	ui.closeBtn = makeButton(controls, "✕", Color3.fromRGB(150, 38, 70), UDim2.fromOffset(28, 28))
	ui.closeBtn.LayoutOrder = 2

	-- Tab bar -------------------------------------------------------------------
	local tabBar = new("Frame", {
		Parent = ui.panel,
		Name = "Tabs",
		Position = UDim2.fromOffset(12, 54),
		Size = UDim2.new(1, -24, 0, 32),
		BackgroundTransparency = 1,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.new(1 / 4, -6, 1, 0),
			CellPadding = UDim2.fromOffset(8, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.tabBtns = {}
	for index, tab in ipairs(TABS) do
		local button = makeButton(tabBar, tab.label, THEME.SurfaceHi)
		button.LayoutOrder = index
		ui.tabBtns[tab.id] = button
	end

	-- Status bar (satu baris, tampil di semua tab) ------------------------------
	local statusBar = new("Frame", {
		Parent = ui.panel,
		Name = "StatusBar",
		Position = UDim2.fromOffset(12, 91),
		Size = UDim2.new(1, -24, 0, 26),
		BackgroundColor3 = THEME.Surface,
		BackgroundTransparency = 0.25,
	}, {
		corner(8),
		padding(10, 0, 10, 0),
	})
	ui.statusLine = new("TextLabel", {
		Parent = statusBar,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = state.statusText,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = THEME.Info,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- Halaman (satu per tab) ----------------------------------------------------
	ui.pages = {}
	local function makePage(id)
		local page = new("ScrollingFrame", {
			Parent = ui.panel,
			Name = "Page_" .. id,
			Position = UDim2.fromOffset(0, 124),
			Size = UDim2.new(1, 0, 1, -124),
			BackgroundTransparency = 1,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = THEME.Accent,
			Visible = false,
		}, {
			padding(12, 4, 12, 12),
			new("UIListLayout", {
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		ui.pages[id] = page
		return page
	end
	local returnPage = makePage("return")
	local findPage = makePage("find")
	local afkPage = makePage("afk")
	local advancedPage = makePage("advanced")

	ui.selectTab = function(id)
		state.tab = id
		for tabId, page in pairs(ui.pages) do
			page.Visible = tabId == id
			ui.tabBtns[tabId].BackgroundColor3 = tabId == id and THEME.AccentDark or THEME.SurfaceHi
		end
	end

	--==========================  TAB RETURN  ==================================--
	local statusCard = makeCard(returnPage, 1)
	makeSectionHeader(statusCard, "STATUS", 1)
	ui.statusInfo = makeLabel(statusCard, "", 12, THEME.Muted, false)
	ui.statusInfo.LayoutOrder = 2

	-- Positions card ------------------------------------------------------------
	local posCard = makeCard(returnPage, 2)
	ui.countLabel = makeSectionHeader(posCard, "POSITIONS", 1)

	local inputRow = makeRow(posCard, 2, 36)
	ui.nameBox = makeTextBox(inputRow, "Nama slot (opsional)", UDim2.new(1, -96, 1, 0))
	ui.nameBox.LayoutOrder = 1
	ui.saveBtn = makeButton(inputRow, "Save", THEME.AccentDark, UDim2.fromOffset(88, 36))
	ui.saveBtn.LayoutOrder = 2

	ui.slotList = new("ScrollingFrame", {
		Parent = posCard,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 132),
		BackgroundColor3 = Color3.fromRGB(14, 10, 24),
		BackgroundTransparency = 0.25,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = THEME.Accent,
	}, {
		corner(10),
		stroke(THEME.Border, 1, 0.6),
		padding(6, 6, 6, 6),
		new("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.emptyLabel = new("TextLabel", {
		Parent = ui.slotList,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "Belum ada posisi tersimpan.",
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = THEME.Muted,
		LayoutOrder = 0,
	})

	local actions = new("Frame", {
		Parent = posCard,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -6, 1, 0),
			CellPadding = UDim2.fromOffset(8, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.returnBtn = makeButton(actions, "Return", THEME.AccentDark)
	ui.returnBtn.LayoutOrder = 1
	ui.deleteBtn = makeButton(actions, "Delete", Color3.fromRGB(150, 38, 70))
	ui.deleteBtn.LayoutOrder = 2
	ui.deleteAllBtn = makeButton(actions, "Delete All", Color3.fromRGB(92, 30, 58))
	ui.deleteAllBtn.LayoutOrder = 3

	-- Auto Return card ----------------------------------------------------------
	local autoCard = makeCard(returnPage, 3)
	makeSectionHeader(autoCard, "AUTO RETURN", 1)
	ui.autoBtn = makeButton(autoCard, "Auto Return: OFF", THEME.SurfaceHi)
	ui.autoBtn.LayoutOrder = 2
	ui.speedSlider = makeSlider(autoCard, 3, "Kecepatan jalan", CONFIG.SpeedMin, CONFIG.SpeedMax, 5, state.walkSpeedPct,
		function(value)
			return string.format("%d%%", value)
		end,
		function(value)
			state.walkSpeedPct = value
		end,
		function()
			persistSavedData()
			setStatus(string.format("Kecepatan jalan: %d%%", state.walkSpeedPct), "info")
		end
	)
	ui.delaySlider = makeSlider(autoCard, 4, "Jeda sebelum jalan (Auto Return)", 0, CONFIG.DelayMax, 1, state.autoDelay,
		function(value)
			return value == 0 and "tanpa jeda" or string.format("%d dtk", value)
		end,
		function(value)
			state.autoDelay = value
		end,
		function()
			persistSavedData()
			setStatus(string.format("Jeda Auto Return: %d dtk", state.autoDelay), "info")
		end
	)
	ui.triggerSlider = makeSlider(autoCard, 5, "Jarak deteksi geser", CONFIG.TriggerMin, CONFIG.TriggerMax, 0.5, state.autoTrigger,
		function(value)
			return string.format("%.1f stud", value)
		end,
		function(value)
			state.autoTrigger = value
		end,
		function()
			persistSavedData()
			setStatus(string.format("Jarak deteksi Auto Return: %.1f stud", state.autoTrigger), "info")
		end
	)
	local autoHint = makeLabel(autoCard, "Selama aktif, jika karakter bergeser lebih jauh dari jarak deteksi dari slot terpilih (respawn, terdorong, dsb.), karakter menunggu jeda (diacak ±20%) lalu berjalan kembali seperti Return manual. Kecepatan berlaku juga untuk Return manual. Auto Return dijeda selama Find berjalan.", 11, THEME.Muted, false)
	autoHint.LayoutOrder = 6

	--==========================  TAB FIND  ====================================--
	-- Kontrol utama (Scan / Start / ESP / Loop) ada paling atas.
	local findCard = makeCard(findPage, 1)
	ui.findCount = makeSectionHeader(findCard, "FIND", 1)
	local findRow = makeRow(findCard, 2, 38)
	ui.scanBtn = makeButton(findRow, "Scan", THEME.SurfaceHi, UDim2.new(0.4, -4, 1, 0))
	ui.scanBtn.LayoutOrder = 1
	ui.findStartBtn = makeButton(findRow, "Start Find", THEME.AccentDark, UDim2.new(0.6, -4, 1, 0))
	ui.findStartBtn.LayoutOrder = 2
	local toggleRow = makeRow(findCard, 3, 36)
	ui.espBtn = makeButton(toggleRow, "ESP: OFF", THEME.SurfaceHi, UDim2.new(0.5, -4, 1, 0))
	ui.espBtn.LayoutOrder = 1
	ui.findLoopBtn = makeButton(toggleRow, "Loop Find: OFF", THEME.SurfaceHi, UDim2.new(0.5, -4, 1, 0))
	ui.findLoopBtn.LayoutOrder = 2
	ui.findResult = makeLabel(findCard, state.find.statusText, 12, THEME.Text, true)
	ui.findResult.LayoutOrder = 4

	-- Daftar hasil + total jumlah.
	local resultCard = makeCard(findPage, 2)
	ui.resultCount = makeSectionHeader(resultCard, "HASIL SCAN", 1)
	ui.resultSummary = makeLabel(resultCard, "Belum dipindai. Tekan Scan atau nyalakan ESP.", 11, THEME.Muted, false)
	ui.resultSummary.LayoutOrder = 2
	ui.resultList = new("ScrollingFrame", {
		Parent = resultCard,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Color3.fromRGB(14, 10, 24),
		BackgroundTransparency = 0.25,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = THEME.Accent,
	}, {
		corner(10),
		stroke(THEME.Border, 1, 0.6),
		padding(8, 6, 8, 6),
		new("UIListLayout", {
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.resultEmpty = new("TextLabel", {
		Parent = ui.resultList,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "Belum ada item.",
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = THEME.Muted,
		LayoutOrder = 0,
	})

	-- Kategori (kata kunci nama) + manual.
	local categoryCard = makeCard(findPage, 3)
	makeSectionHeader(categoryCard, "KATEGORI", 1)
	local chipGrid = new("Frame", {
		Parent = categoryCard,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -6, 0, 36),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.findChips = {}
	for index, category in ipairs(FIND_CATEGORIES) do
		local chip = makeButton(chipGrid, category.label, THEME.SurfaceHi)
		chip.LayoutOrder = index
		ui.findChips[category.id] = chip
		connect(chip.Activated, function()
			state.find.categories[category.id] = not state.find.categories[category.id]
			onScanCriteriaChanged()
		end)
	end
	ui.findBox = makeTextBox(categoryCard, "Cari manual: nama objek (pisah koma)", UDim2.new(1, 0, 0, 36))
	ui.findBox.LayoutOrder = 3
	ui.findBox.Text = state.find.custom

	-- Filter tipe: jenis objek + pemicu ambil.
	local typeCard = makeCard(findPage, 4)
	makeSectionHeader(typeCard, "FILTER TIPE ITEM", 1)
	local kindLabel = makeLabel(typeCard, "Jenis objek (angka = jumlah hasil scan)", 11, THEME.Muted, false)
	kindLabel.LayoutOrder = 2
	local kindGrid = new("Frame", {
		Parent = typeCard,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -6, 0, 36),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.kindChips = {}
	for index, kind in ipairs(FIND_KINDS) do
		local chip = makeButton(kindGrid, kind.label, THEME.SurfaceHi)
		chip.LayoutOrder = index
		ui.kindChips[kind.id] = chip
		connect(chip.Activated, function()
			state.find.kinds[kind.id] = not state.find.kinds[kind.id]
			onFilterChanged()
		end)
	end
	local triggerLabel = makeLabel(typeCard, "Cara item diambil (matikan \"Tanpa pemicu\" agar hanya item yang benar-benar bisa diambil)", 11, THEME.Muted, false)
	triggerLabel.LayoutOrder = 4
	local triggerGrid = new("Frame", {
		Parent = typeCard,
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, 36),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.triggerChips = {}
	for index, trigger in ipairs(FIND_TRIGGERS) do
		local chip = makeButton(triggerGrid, trigger.label, THEME.SurfaceHi)
		chip.LayoutOrder = index
		ui.triggerChips[trigger.id] = chip
		connect(chip.Activated, function()
			state.find.triggers[trigger.id] = not state.find.triggers[trigger.id]
			-- "Tanpa pemicu" mengubah cara scan (pencocokan lewat Model induk); minta scan ulang.
			if trigger.id == "plain" then
				esp.nextScan = 0
			end
			onFilterChanged()
		end)
	end

	-- Navigasi.
	local navCard = makeCard(findPage, 5)
	makeSectionHeader(navCard, "NAVIGASI", 1)
	local avoidRow = makeRow(navCard, 2, 36)
	ui.avoidWaterBtn = makeButton(avoidRow, "Hindari Air", THEME.SurfaceHi, UDim2.new(0.5, -4, 1, 0))
	ui.avoidWaterBtn.LayoutOrder = 1
	ui.avoidHazardBtn = makeButton(avoidRow, "Hindari Bahaya", THEME.SurfaceHi, UDim2.new(0.5, -4, 1, 0))
	ui.avoidHazardBtn.LayoutOrder = 2
	local jumpRow = makeRow(navCard, 3, 36)
	ui.findHighJumpBtn = makeButton(jumpRow, "Jump Coin/Gold: ON", THEME.AccentDark, UDim2.new(0.5, -4, 1, 0))
	ui.findHighJumpBtn.LayoutOrder = 1
	ui.findModeBtn = makeButton(jumpRow, "Mode: BERJALAN", THEME.SurfaceHi, UDim2.new(0.5, -4, 1, 0))
	ui.findModeBtn.LayoutOrder = 2

	ui.findStandoffSlider = makeSlider(navCard, 4, "Jarak teleport dari item", CONFIG.FindStandoffMin, CONFIG.FindStandoffMax, 1, state.find.standoff,
		function(value)
			return string.format("%d stud", value)
		end,
		function(value)
			state.find.standoff = value
		end,
		function()
			persistSavedData()
			setStatus(string.format("Jarak teleport Find: %d stud", state.find.standoff), "info")
		end
	)
	ui.findSpeedSlider = makeSlider(navCard, 5, "Kecepatan Find", CONFIG.SpeedMin, CONFIG.SpeedMax, 5, state.find.speedPct,
		function(value)
			return string.format("%d%%", value)
		end,
		function(value)
			state.find.speedPct = value
			-- Berlaku langsung walau Find sedang berjalan.
			local walk = state.walk
			if state.find.running and walk and walk.humanoid and walk.humanoid.Parent then
				walk.humanoid.WalkSpeed = walk.original * value / 100
			end
		end,
		function()
			persistSavedData()
			setStatus(string.format("Kecepatan Find: %d%%", state.find.speedPct), "info")
		end
	)

	-- Auto interaksi per kategori.
	local interactCard = makeCard(findPage, 6)
	makeSectionHeader(interactCard, "AUTO INTERAKSI", 1)
	local interactHeader = makeLabel(interactCard, "Toggle mengaktifkan, tombol Key untuk custom keybind per kategori", 11, THEME.Muted, false)
	interactHeader.LayoutOrder = 2
	ui.findInteractBtns = {}
	ui.findKeyBtns = {}
	for index, category in ipairs(FIND_CATEGORIES) do
		local interactionRow = makeRow(interactCard, 2 + index, 32)
		local interactBtn = makeButton(interactionRow, category.label .. " Auto: OFF", THEME.SurfaceHi, UDim2.new(0.58, -4, 1, 0))
		interactBtn.LayoutOrder = 1
		local keyBtn = makeButton(interactionRow, "Key: E", THEME.SurfaceHi, UDim2.new(0.42, -4, 1, 0))
		keyBtn.LayoutOrder = 2
		ui.findInteractBtns[category.id] = interactBtn
		ui.findKeyBtns[category.id] = keyBtn
		connect(interactBtn.Activated, function()
			state.find.interactEnabled[category.id] = not state.find.interactEnabled[category.id]
			persistSavedData()
			refreshFindUI()
		end)
		connect(keyBtn.Activated, function()
			state.capturingKey = false
			state.capturingFindKey = category.id
			refreshFindUI()
			notify("Keybind " .. category.label .. ": tekan tombol keyboard baru (Esc untuk batal).", "info")
		end)
	end
	local findHint = makeLabel(findPage, "Scan menghitung item; Start Find memproses yang terdekat dulu. Mode TELEPORT tidak langsung ke item: karakter dipindah ke titik beberapa stud dari item, lalu berjalan / loncat / berenang mendekat dan bolak-balik melewati item sampai terambil. Item di air didekati dengan berenang (matikan Hindari Air). ESP menandai item di layar. Tiap item diberi waktu 15 detik sebelum dilewati. Tombol gerak (WASD) atau Stop membatalkan.", 11, THEME.Muted, false)
	findHint.LayoutOrder = 7

	--==========================  TAB AFK  =====================================--
	local afkCard = makeCard(afkPage, 1)
	makeSectionHeader(afkCard, "ANTI-AFK", 1)
	ui.afkBtn = makeButton(afkCard, "Anti-AFK: OFF", THEME.SurfaceHi)
	ui.afkBtn.LayoutOrder = 2
	local afkRow = makeRow(afkCard, 3, 36)
	ui.keyBtn = makeButton(afkRow, "Keybind", THEME.SurfaceHi, UDim2.new(0.5, -4, 1, 0))
	ui.keyBtn.LayoutOrder = 1
	ui.durationBox, ui.durationStroke = makeTextBox(afkRow, "Interval menit (maks 19)", UDim2.new(0.5, -4, 1, 0))
	ui.durationBox.LayoutOrder = 2
	ui.durationBox.Text = tostring(state.afk.minutes)
	ui.applyDurationBtn = makeButton(afkCard, "Set Interval", THEME.AccentDark)
	ui.applyDurationBtn.LayoutOrder = 4
	ui.afkCountdown = makeLabel(afkCard, "Tekan berikutnya: --:--", 12, THEME.Text, true)
	ui.afkCountdown.LayoutOrder = 5
	local afkNote = makeLabel(afkCard, "Tombol terpilih ditekan sekali saat dinyalakan (tes), lalu diulang tiap interval sampai dimatikan. Tidak menjamin bebas dari semua sistem idle atau kebijakan server.", 11, THEME.Muted, false)
	afkNote.LayoutOrder = 6

	--==========================  TAB ADVANCED  ================================--
	local autoExecCard = makeCard(advancedPage, 1)
	makeSectionHeader(autoExecCard, "AUTOEXECUTE SAAT TELEPORT / REJOIN", 1)
	ui.autoExecuteBtn = makeButton(autoExecCard, "Autoexecute: OFF", THEME.SurfaceHi)
	ui.autoExecuteBtn.LayoutOrder = 2
	ui.autoExecuteUrlBox = makeTextBox(autoExecCard, "URL raw script (https://...)", UDim2.new(1, 0, 0, 36))
	ui.autoExecuteUrlBox.LayoutOrder = 3
	ui.autoExecuteUrlBox.Text = state.advanced.scriptUrl
	ui.autoExecuteSaveBtn = makeButton(autoExecCard, "Simpan URL", THEME.AccentDark)
	ui.autoExecuteSaveBtn.LayoutOrder = 4
	ui.autoExecuteHint = makeLabel(autoExecCard, "Perlu executor yang menyediakan queue_on_teleport dan URL raw script yang bisa diakses. Saat ON, script akan dimuat ulang setelah teleport, lalu menyiapkan antrean untuk teleport berikutnya. Ini tidak dapat menjamin auto-run setelah menutup Roblox secara manual.", 11, THEME.Muted, false)
	ui.autoExecuteHint.LayoutOrder = 5

	local antiStuckCard = makeCard(advancedPage, 2)
	makeSectionHeader(antiStuckCard, "ANTI-SIT / ANTI-STUCK", 1)
	ui.antiStuckBtn = makeButton(antiStuckCard, "Anti-Stuck: ON", THEME.AccentDark)
	ui.antiStuckBtn.LayoutOrder = 2
	local antiStuckNote = makeLabel(antiStuckCard, "Mencoba berdiri otomatis dari Seat/VehicleSeat, memulihkan PlatformStand/FallingDown/Ragdoll, dan memberi lompatan pemulihan jika karakter menerima input gerak tetapi tidak berpindah. Efek yang dikunci oleh server/game tertentu tetap bisa membatasi pemulihan client.", 11, THEME.Muted, false)
	antiStuckNote.LayoutOrder = 3

	for tabId, button in pairs(ui.tabBtns) do
		connect(button.Activated, function()
			ui.selectTab(tabId)
		end)
	end
	ui.selectTab(state.tab)

	-- Confirm overlay -----------------------------------------------------------
	ui.confirmOverlay = new("Frame", {
		Parent = ui.panel,
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		Active = true,
		Visible = false,
		ZIndex = 20,
	})
	local confirmCard = new("Frame", {
		Parent = ui.confirmOverlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.86, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Surface,
		BackgroundTransparency = 0.02,
		ZIndex = 21,
	}, {
		corner(16),
		stroke(THEME.Accent, 1.2, 0.3),
		padding(14, 14, 14, 14),
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	ui.confirmMessage = makeLabel(confirmCard, "", 13, THEME.Text, true)
	ui.confirmMessage.LayoutOrder = 1
	ui.confirmMessage.ZIndex = 22
	local confirmRow = makeRow(confirmCard, 2, 36)
	ui.confirmNo = makeButton(confirmRow, "Batal", THEME.SurfaceHi, UDim2.new(0.5, -4, 1, 0))
	ui.confirmNo.LayoutOrder = 1
	ui.confirmNo.ZIndex = 22
	ui.confirmYes = makeButton(confirmRow, "Hapus", Color3.fromRGB(170, 40, 78), UDim2.new(0.5, -4, 1, 0))
	ui.confirmYes.LayoutOrder = 2
	ui.confirmYes.ZIndex = 22

	-- Pill (restore handle) -----------------------------------------------------
	ui.pill = new("TextButton", {
		Parent = gui,
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(60, gui.AbsoluteSize.Y * 0.4),
		Size = UDim2.fromOffset(92, 34),
		BackgroundColor3 = Color3.fromRGB(34, 18, 54),
		BackgroundTransparency = 0.04,
		Text = "◆ ISEKAI",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = THEME.Text,
		AutoButtonColor = true,
		Visible = false,
		ZIndex = 5,
	}, {
		corner(17),
		stroke(THEME.Accent, 1.3, 0.3),
	})

	-- Toast holder --------------------------------------------------------------
	ui.toastHolder = new("Frame", {
		Parent = gui,
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 100,
	}, {
		new("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	-- Interaksi -----------------------------------------------------------------
	local headerDrag = makeDraggable(header, ui.root)
	local pillDrag = makeDraggable(ui.pill, ui.pill)
	headerDrag.moved = false

	connect(ui.minimizeBtn.Activated, function()
		setMinimized(true)
	end)
	connect(ui.closeBtn.Activated, function()
		cleanup()
	end)
	connect(ui.pill.Activated, function()
		if not pillDrag.moved then
			setMinimized(false)
		end
	end)

	connect(ui.saveBtn.Activated, function()
		savePosition(ui.nameBox.Text)
	end)
	connect(ui.nameBox.FocusLost, function(enterPressed)
		if enterPressed then
			savePosition(ui.nameBox.Text)
		end
	end)
	connect(ui.returnBtn.Activated, function()
		if state.busy then
			cancelMove()
		else
			moveToSavedSpot(getSelectedSlot(), "manual")
		end
	end)
	connect(ui.deleteBtn.Activated, function()
		local slot = getSelectedSlot()
		if not slot then
			notify("Pilih slot yang ingin dihapus.", "warning")
			return
		end
		askConfirm(string.format("Hapus posisi \"%s\"?", slot.name), "Hapus", function()
			deletePosition(slot.id)
		end)
	end)
	connect(ui.deleteAllBtn.Activated, function()
		if #state.slots == 0 then
			notify("Tidak ada data untuk dihapus.", "info")
			return
		end
		local here = #visibleSlots()
		askConfirm(
			string.format("Hapus SEMUA data tersimpan?\n%d slot di game ini, %d slot di game lain.", here, #state.slots - here),
			"Hapus Semua",
			deleteAllPositions
		)
	end)
	connect(ui.confirmNo.Activated, hideConfirm)
	connect(ui.confirmYes.Activated, function()
		local callback = ui.confirmCallback
		hideConfirm()
		if callback then
			callback()
		end
	end)

	-- Find
	connect(ui.findBox.FocusLost, function()
		state.find.custom = sanitizeKeywords(ui.findBox.Text)
		onScanCriteriaChanged()
	end)
	connect(ui.avoidWaterBtn.Activated, function()
		state.find.avoidWater = not state.find.avoidWater
		persistSavedData()
		refreshFindUI()
	end)
	connect(ui.avoidHazardBtn.Activated, function()
		state.find.avoidHazard = not state.find.avoidHazard
		esp.nextScan = 0
		persistSavedData()
		refreshFindUI()
	end)
	connect(ui.findLoopBtn.Activated, function()
		state.find.loopEnabled = not state.find.loopEnabled
		persistSavedData()
		refreshFindUI()
		if state.find.loopEnabled then
			notify("Loop Find ON: setelah satu ronde, script akan scan ulang sampai dimatikan atau Stop ditekan.", "success")
		else
			notify("Loop Find OFF: Find berhenti mengulang setelah ronde berjalan selesai.", "info")
		end
	end)
	connect(ui.findHighJumpBtn.Activated, function()
		state.find.jumpHighCoinGold = not state.find.jumpHighCoinGold
		persistSavedData()
		refreshFindUI()
	end)
	connect(ui.findModeBtn.Activated, function()
		state.find.mode = state.find.mode == "walk" and "teleport" or "walk"
		persistSavedData()
		refreshFindUI()
		notify("Mode Find: " .. (state.find.mode == "walk" and "Berjalan" or "Teleport berjarak"), "info")
	end)
	connect(ui.espBtn.Activated, function()
		setEsp(not state.find.espEnabled)
	end)
	connect(ui.scanBtn.Activated, function()
		startFind(true)
	end)
	connect(ui.findStartBtn.Activated, function()
		if state.find.running or state.find.scanning then
			stopFind()
		else
			startFind(false)
		end
	end)

	connect(ui.autoExecuteSaveBtn.Activated, function()
		local url = (ui.autoExecuteUrlBox.Text or ""):match("^%s*(.-)%s*$") or ""
		if (url ~= "" and not isValidHttpUrl(url)) or (state.advanced.autoExecuteEnabled and not isValidHttpUrl(url)) then
			notify("URL tidak valid. Saat Autoexecute ON, URL raw wajib diawali http:// atau https:// (maks. " .. CONFIG.AutoExecuteUrlMaxLength .. " karakter).", "warning")
			return
		end
		state.advanced.scriptUrl = url
		setAutoExecuteGlobals(state.advanced.autoExecuteEnabled, url)
		persistSavedData()
		if state.advanced.autoExecuteEnabled then
			local queued, message = queueAutoExecute()
			notify(message, queued and "success" or "warning")
		else
			notify(url == "" and "URL autoexecute dikosongkan." or "URL autoexecute berhasil disimpan.", "success")
		end
		refreshUI()
	end)
	connect(ui.autoExecuteUrlBox.FocusLost, function(enterPressed)
		if enterPressed then
			ui.autoExecuteSaveBtn:Activate()
		end
	end)
	connect(ui.autoExecuteBtn.Activated, function()
		if state.advanced.autoExecuteEnabled then
			state.advanced.autoExecuteEnabled = false
			setAutoExecuteGlobals(false, state.advanced.scriptUrl)
			persistSavedData()
			local queued, message = queueAutoExecute()
			refreshUI()
			notify(queued and "Autoexecute dimatikan." or ("Autoexecute dimatikan, tetapi antrean executor tidak bisa dibersihkan: " .. tostring(message)), queued and "info" or "warning")
			return
		end

		local url = (ui.autoExecuteUrlBox.Text or ""):match("^%s*(.-)%s*$") or ""
		if not isValidHttpUrl(url) then
			notify("Isi URL raw script yang valid lalu tekan Simpan URL.", "warning")
			return
		end
		state.advanced.scriptUrl = url
		state.advanced.autoExecuteEnabled = true
		setAutoExecuteGlobals(true, url)
		persistSavedData()
		local queued, message = queueAutoExecute()
		if not queued then
			state.advanced.autoExecuteEnabled = false
			setAutoExecuteGlobals(false, url)
			persistSavedData()
		end
		refreshUI()
		notify(message, queued and "success" or "error")
	end)
	connect(ui.antiStuckBtn.Activated, function()
		state.advanced.antiStuckEnabled = not state.advanced.antiStuckEnabled
		persistSavedData()
		refreshUI()
		notify("Anti-Stuck " .. (state.advanced.antiStuckEnabled and "diaktifkan." or "dimatikan."), state.advanced.antiStuckEnabled and "success" or "info")
	end)

	connect(ui.autoBtn.Activated, toggleAutoReturn)
	connect(ui.afkBtn.Activated, toggleAntiAFK)
	connect(ui.keyBtn.Activated, beginKeyCapture)
	connect(ui.applyDurationBtn.Activated, function()
		applyDuration(true)
	end)
	connect(ui.durationBox.FocusLost, function(enterPressed)
		-- Enter selalu menerapkan; kehilangan fokus biasa (mis. tap di luar) menerapkan jika isinya berubah.
		if enterPressed or ui.durationBox.Text ~= tostring(state.afk.minutes) then
			applyDuration(true)
		end
	end)
	connect(ui.durationBox:GetPropertyChangedSignal("Text"), function()
		ui.durationStroke.Color = THEME.Border
	end)
	connect(gui:GetPropertyChangedSignal("AbsoluteSize"), layoutUI)

	layoutUI()
end

--------------------------------------------------------------------------------
-- UI REFRESH
--------------------------------------------------------------------------------

local function refreshSlotList()
	for _, child in ipairs(ui.slotList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local list = visibleSlots()
	ui.emptyLabel.Visible = #list == 0
	ui.countLabel.Text = string.format("%d/%d", #list, CONFIG.MaxSlots)

	for index, slot in ipairs(list) do
		local selected = slot.id == state.selectedId
		local position = slot.cf.Position
		local row = new("TextButton", {
			Parent = ui.slotList,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 40),
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = selected and Color3.fromRGB(62, 28, 86) or THEME.Surface,
			BackgroundTransparency = 0.05,
		}, {
			corner(10),
			stroke(selected and THEME.Accent or THEME.Border, 1, selected and 0.1 or 0.6),
		})
		new("TextLabel", {
			Parent = row,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(0, 16, 1, 0),
			BackgroundTransparency = 1,
			Text = selected and "●" or "○",
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = selected and THEME.Accent or THEME.Muted,
		})
		new("TextLabel", {
			Parent = row,
			Position = UDim2.fromOffset(30, 4),
			Size = UDim2.new(1, -40, 0, 16),
			BackgroundTransparency = 1,
			Text = slot.name,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = THEME.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		new("TextLabel", {
			Parent = row,
			Position = UDim2.fromOffset(30, 21),
			Size = UDim2.new(1, -40, 0, 14),
			BackgroundTransparency = 1,
			Text = string.format("X %.1f  Y %.1f  Z %.1f  •  %s", position.X, position.Y, position.Z, os.date("%d/%m %H:%M", slot.savedAt)),
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		row.Activated:Connect(function()
			selectSlot(slot.id)
		end)
	end
end

refreshStatus = function()
	if state.closed or not ui.statusLine then
		return
	end
	ui.statusLine.Text = state.statusText
	ui.statusLine.TextColor3 = KIND_COLOR[state.statusKind] or THEME.Info

	local slot = getSelectedSlot()
	local afkText = "OFF"
	if state.afk.active then
		afkText = "ON (" .. formatTime(state.afk.endsAt - os.clock()) .. ")"
	end
	local findText = "OFF"
	if state.find.running then
		findText = string.format("%d/%d", state.find.done, state.find.total)
	elseif state.find.scanning then
		findText = "memindai"
	end
	ui.statusInfo.Text = string.format(
		"Slot aktif : %s\nAuto Return : %s\nAnti-AFK : %s\nFind : %s%s\nStorage : %s",
		slot and slot.name or "-",
		state.autoReturn and "ON" or "OFF",
		afkText,
		findText,
		state.find.espEnabled and " • ESP ON" or "",
		state.storage.mode
	)
end

refreshFindUI = function()
	if state.closed or not ui.findStartBtn then
		return
	end
	local find = state.find
	local function tint(button, on)
		button.BackgroundColor3 = on and THEME.AccentDark or THEME.SurfaceHi
	end

	for _, category in ipairs(FIND_CATEGORIES) do
		local chip = ui.findChips[category.id]
		local on = find.categories[category.id] == true
		local count = on and find.counts[category.id]
		chip.Text = (on and "✓ " or "") .. category.label .. (count and count > 0 and (" " .. count) or "")
		tint(chip, on)
	end

	for _, kind in ipairs(FIND_KINDS) do
		local chip = ui.kindChips[kind.id]
		local on = find.kinds[kind.id] == true
		local count = find.kindCounts[kind.id]
		chip.Text = (on and "✓ " or "") .. kind.label .. (find.scanned and (" " .. count) or "")
		tint(chip, on)
	end
	for _, trigger in ipairs(FIND_TRIGGERS) do
		local chip = ui.triggerChips[trigger.id]
		local on = find.triggers[trigger.id] == true
		local count = find.trigCounts[trigger.id]
		chip.Text = (on and "✓ " or "") .. trigger.label .. (find.scanned and (" " .. count) or "")
		tint(chip, on)
	end

	ui.avoidWaterBtn.Text = find.avoidWater and "Hindari Air: ON" or "Hindari Air: OFF"
	tint(ui.avoidWaterBtn, find.avoidWater)
	ui.avoidHazardBtn.Text = find.avoidHazard and "Hindari Bahaya: ON" or "Hindari Bahaya: OFF"
	tint(ui.avoidHazardBtn, find.avoidHazard)

	ui.findLoopBtn.Text = find.loopEnabled and "Loop Find: ON" or "Loop Find: OFF"
	tint(ui.findLoopBtn, find.loopEnabled)
	ui.espBtn.Text = find.espEnabled and "ESP: ON" or "ESP: OFF"
	tint(ui.espBtn, find.espEnabled)
	ui.findHighJumpBtn.Text = find.jumpHighCoinGold and "Jump Coin/Gold: ON" or "Jump Coin/Gold: OFF"
	tint(ui.findHighJumpBtn, find.jumpHighCoinGold)
	ui.findModeBtn.Text = find.mode == "teleport" and "Mode: TELEPORT" or "Mode: BERJALAN"
	tint(ui.findModeBtn, find.mode == "teleport")

	for _, category in ipairs(FIND_CATEGORIES) do
		local enabled = find.interactEnabled[category.id] == true
		local interactBtn = ui.findInteractBtns[category.id]
		local keyBtn = ui.findKeyBtns[category.id]
		interactBtn.Text = category.label .. " Auto: " .. (enabled and "ON" or "OFF")
		tint(interactBtn, enabled)
		if state.capturingFindKey == category.id then
			keyBtn.Text = "Tekan tombol..."
			keyBtn.BackgroundColor3 = THEME.Accent
		else
			local keyCode = find.interactKeys[category.id]
			keyBtn.Text = "Key: " .. (keyCode and keyCode.Name or "E")
			keyBtn.BackgroundColor3 = THEME.SurfaceHi
		end
	end

	local active = find.running or find.scanning
	ui.findStartBtn.Text = active and "Stop Find" or "Start Find"
	ui.findStartBtn.BackgroundColor3 = active and Color3.fromRGB(190, 110, 30) or THEME.AccentDark
	ui.scanBtn.Text = find.scanning and "Memindai..." or "Scan"

	if find.running then
		ui.findCount.Text = string.format("%d/%d", find.done, find.total)
	elseif #find.results > 0 then
		ui.findCount.Text = string.format("%d item", #find.results)
	else
		ui.findCount.Text = ""
	end
	ui.findResult.Text = find.statusText
	ui.findSpeedSlider.set(find.speedPct)
	ui.findStandoffSlider.set(find.standoff)
	refreshStatus()
end

refreshUI = function()
	if state.closed or not ui.gui then
		return
	end
	refreshSlotList()
	refreshStatus()

	ui.autoBtn.Text = state.autoReturn and "Auto Return: ON" or "Auto Return: OFF"
	ui.autoBtn.BackgroundColor3 = state.autoReturn and THEME.AccentDark or THEME.SurfaceHi

	ui.afkBtn.Text = state.afk.active and "Anti-AFK: ON" or "Anti-AFK: OFF"
	ui.afkBtn.BackgroundColor3 = state.afk.active and THEME.AccentDark or THEME.SurfaceHi

	if ui.autoExecuteBtn then
		ui.autoExecuteBtn.Text = state.advanced.autoExecuteEnabled and "Autoexecute: ON" or "Autoexecute: OFF"
		ui.autoExecuteBtn.BackgroundColor3 = state.advanced.autoExecuteEnabled and THEME.AccentDark or THEME.SurfaceHi
	end
	if ui.antiStuckBtn then
		ui.antiStuckBtn.Text = state.advanced.antiStuckEnabled and "Anti-Stuck: ON" or "Anti-Stuck: OFF"
		ui.antiStuckBtn.BackgroundColor3 = state.advanced.antiStuckEnabled and THEME.AccentDark or THEME.SurfaceHi
	end
	if ui.autoExecuteUrlBox and not ui.autoExecuteUrlBox:IsFocused() then
		ui.autoExecuteUrlBox.Text = state.advanced.scriptUrl
	end

	if state.capturingKey then
		ui.keyBtn.Text = "Tekan tombol..."
		ui.keyBtn.BackgroundColor3 = THEME.Accent
	else
		ui.keyBtn.Text = "Tombol: " .. state.afk.keyCode.Name
		ui.keyBtn.BackgroundColor3 = THEME.SurfaceHi
	end

	if not state.afk.active then
		ui.afkCountdown.Text = "Tekan berikutnya: --:--"
	end

	ui.returnBtn.Text = state.busy and "Stop" or "Return"
	ui.returnBtn.BackgroundColor3 = state.busy and Color3.fromRGB(190, 110, 30) or THEME.AccentDark
	ui.speedSlider.set(state.walkSpeedPct)
	ui.delaySlider.set(state.autoDelay)
	ui.triggerSlider.set(state.autoTrigger)
	refreshFindUI()
end

--------------------------------------------------------------------------------
-- INTRO (4 detik)
--------------------------------------------------------------------------------

local function showMainPanel()
	state.uiReady = true
	ui.root.Visible = true
	ui.rootScale.Scale = 0.94
	ui.panel.GroupTransparency = 1
	tween(ui.panel, 0.35, { GroupTransparency = 0 })
	tween(ui.rootScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	for _, notice in ipairs(pendingNotices) do
		showNotification(notice[1], notice[2])
	end
	table.clear(pendingNotices)
	refreshUI()
end

local function playIntro()
	local overlay = new("Frame", {
		Parent = ui.gui,
		Name = "Intro",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(5, 3, 10),
		BackgroundTransparency = 1,
		ZIndex = 50,
	})
	local scale = new("UIScale", { Scale = 0.8 })
	local card = new("CanvasGroup", {
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 360, 0, 200),
		BackgroundColor3 = THEME.Background,
		BackgroundTransparency = 1,
		GroupTransparency = 1,
	}, {
		corner(22),
		stroke(THEME.Accent, 1.5, 0.35),
		scale,
	})
	new("Frame", {
		Parent = card,
		Name = "Glass",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.02,
		ZIndex = 0,
	}, {
		new("UIGradient", { Rotation = 135, Color = ColorSequence.new(THEME.BackgroundAlt, THEME.Background) }),
	})
	local title = new("TextLabel", {
		Parent = card,
		Position = UDim2.fromOffset(12, 20),
		Size = UDim2.new(1, -24, 0, 48),
		BackgroundTransparency = 1,
		Text = CONFIG.IntroTitle,
		Font = Enum.Font.GothamBlack,
		TextSize = 38,
		TextColor3 = THEME.Text,
		TextScaled = true,
	}, { new("UITextSizeConstraint", { MaxTextSize = 38, MinTextSize = 14 }) })
	new("TextLabel", {
		Parent = card,
		Position = UDim2.fromOffset(12, 70),
		Size = UDim2.new(1, -24, 0, 14),
		BackgroundTransparency = 1,
		Text = CONFIG.Credit,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextColor3 = THEME.Text,
		TextTransparency = 0.5,
	})
	new("TextLabel", {
		Parent = card,
		Position = UDim2.fromOffset(12, 94),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundTransparency = 1,
		Text = CONFIG.Subtitle,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = THEME.Muted,
	})
	local track = new("Frame", {
		Parent = card,
		Position = UDim2.new(0, 28, 0, 138),
		Size = UDim2.new(1, -56, 0, 6),
		BackgroundColor3 = Color3.fromRGB(40, 28, 62),
	}, { corner(3) })
	local fill = new("Frame", {
		Parent = track,
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.AccentDark,
	}, { corner(3) })
	local stage = new("TextLabel", {
		Parent = card,
		Position = UDim2.fromOffset(12, 156),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundTransparency = 1,
		Text = "Menyiapkan sistem...",
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextColor3 = THEME.Muted,
	})

	local holdTime = CONFIG.IntroDuration - CONFIG.IntroFadeOut
	tween(overlay, 0.4, { BackgroundTransparency = 0.35 })
	tween(card, 0.6, { GroupTransparency = 0 })
	tween(scale, 0.7, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(fill, holdTime - 0.2, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = THEME.Accent }, Enum.EasingStyle.Linear)
	tween(title, holdTime - 0.4, { TextColor3 = Color3.fromRGB(240, 150, 236) }, Enum.EasingStyle.Sine)

	spawnTask(function()
		task.wait(holdTime * 0.35)
		if state.closed then return end
		stage.Text = "Memuat data posisi..."
		task.wait(holdTime * 0.35)
		if state.closed then return end
		stage.Text = "Menyiapkan antarmuka..."
		task.wait(holdTime * 0.3)
		if state.closed then return end
		stage.Text = "Siap."
		tween(card, CONFIG.IntroFadeOut, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(scale, CONFIG.IntroFadeOut, { Scale = 1.06 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(overlay, CONFIG.IntroFadeOut, { BackgroundTransparency = 1 })
		task.wait(CONFIG.IntroFadeOut)
		if state.closed then return end
		overlay:Destroy()
		showMainPanel()
	end)
end

--------------------------------------------------------------------------------
-- GLOBAL ANTI-STUCK MONITOR
--------------------------------------------------------------------------------

local antiStuckGeneration = 0
local function startAntiStuckMonitor(character)
	antiStuckGeneration += 1
	local generation = antiStuckGeneration
	spawnTask(function()
		if not character or not character.Parent then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
		local root = character:FindFirstChild("HumanoidRootPart") or (humanoid and humanoid.RootPart)
		if not humanoid or not root then
			return
		end

		local lastPosition = root.Position
		local lastMotionAt = os.clock()
		local lastRecoveryAt = 0
		local seatSince = nil
		while not state.closed and generation == antiStuckGeneration and player.Character == character do
			if state.advanced.antiStuckEnabled and humanoid.Parent and humanoid.Health > 0 and root.Parent then
				local now = os.clock()
				local position = root.Position
				local humanoidState = humanoid:GetState()
				local seated = isSeated(humanoid)

				if seated then
					seatSince = seatSince or now
					if now - lastRecoveryAt >= 0.75 then
						lastRecoveryAt = now
						pcall(function()
							humanoid.Sit = false
							humanoid.Jump = true
							humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
						end)
					end
					if now - seatSince >= 1.5 then
						-- Sebagian Seat/VehicleSeat langsung memasang ulang joint; naik sedikit untuk melepaskan diri.
						pcall(function()
							humanoid.Sit = false
							root.CFrame = root.CFrame + Vector3.new(0, 2, 0)
							root.AssemblyLinearVelocity = Vector3.zero
							humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
						end)
						seatSince = now
					end
				else
					seatSince = nil
					if (position - lastPosition).Magnitude >= 0.75 then
						lastPosition = position
						lastMotionAt = now
					end

					if now - lastRecoveryAt >= 0.75 then
						if humanoid.PlatformStand or humanoidState == Enum.HumanoidStateType.PlatformStanding then
							lastRecoveryAt = now
							pcall(function()
								humanoid.PlatformStand = false
								humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
							end)
						elseif humanoidState == Enum.HumanoidStateType.FallingDown or humanoidState == Enum.HumanoidStateType.Ragdoll then
							lastRecoveryAt = now
							pcall(function()
								humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
							end)
						end
					end

					-- Recovery ringan saat pemain sedang memberi input, tetapi posisi benar-benar tidak berubah.
					if not state.busy and humanoid.MoveDirection.Magnitude > 0.1 and now - lastMotionAt >= CONFIG.AntiStuckMoveTimeout and now - lastRecoveryAt >= 2 then
						lastRecoveryAt = now
						lastMotionAt = now
						pcall(function()
							root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, math.max(root.AssemblyLinearVelocity.Y, 0), root.AssemblyLinearVelocity.Z)
								humanoid.Jump = true
							humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
						end)
					end
				end
			end
			task.wait(CONFIG.AntiStuckPollInterval)
		end
	end)
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

cleanup = function()
	if state.closed then
		return
	end
	-- Simpan dulu selagi state masih utuh, lalu tandai closed.
	persistSavedData()
	state.closed = true
	state.find.token += 1
	state.find.running = false
	state.find.scanning = false
	state.find.espEnabled = false
	state.afk.active = false
	state.afk.token += 1
	state.moveToken += 1
	state.busy = false
	restoreWalkSpeed()

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)

	for activeTween in pairs(activeTweens) do
		activeTween:Cancel()
	end
	table.clear(activeTweens)

	local current = coroutine.running()
	for _, thread in ipairs(tasks) do
		if thread ~= current and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
	end
	table.clear(tasks)
	table.clear(toastQueue)
	table.clear(toastMessages)

	esp.token += 1
	if esp.gui then
		esp.gui:Destroy()
		esp.gui = nil
	end
	table.clear(esp.items)
	if ui.gui then
		ui.gui:Destroy()
	end

	local registered = globalEnv[INSTANCE_KEY]
	if type(registered) == "table" and registered.Id == state then
		globalEnv[INSTANCE_KEY] = nil
	end
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

detectStorage()
loadSavedData()
-- State dari queue payload punya prioritas saat executor tidak menyediakan penyimpanan file.
if globalEnv.__IsekaiReturnSystemAutoExecuteManaged == true then
	state.advanced.autoExecuteEnabled = globalEnv.__IsekaiReturnSystemAutoExecuteEnabled == true
	if type(globalEnv.__IsekaiReturnSystemAutoExecuteURL) == "string" then
		state.advanced.scriptUrl = globalEnv.__IsekaiReturnSystemAutoExecuteURL
	end
end
local resumeFindAfterTeleport = globalEnv.__IsekaiReturnSystemResumeFindAfterTeleport == true
globalEnv.__IsekaiReturnSystemResumeFindAfterTeleport = false
buildUI()

connect(player.CharacterRemoving, function()
	antiStuckGeneration += 1
	onCharacterRemoving()
end)
connect(player.CharacterAdded, function(character)
	startAntiStuckMonitor(character)
end)
if player.Character then
	startAntiStuckMonitor(player.Character)
end
connect(UserInputService.InputBegan, onInputBegan)
connect(player.Idled, onIdled)

globalEnv[INSTANCE_KEY] = { Cleanup = cleanup, Id = state }

if state.advanced.autoExecuteEnabled then
	local queued, message = queueAutoExecute()
	table.insert(pendingNotices, { message, queued and "success" or "warning" })
end

-- Pulihkan Anti-AFK bila aktif saat terakhir disimpan.
if state.afk.resume then
	state.afk.resume = false
	startAntiAFK(state.afk.minutes)
	table.insert(pendingNotices, {
		string.format("Anti-AFK dipulihkan: menekan %s tiap %d menit.", state.afk.keyCode.Name, state.afk.minutes),
		"success",
	})
end

if state.autoReturn and getSelectedSlot() then
	table.insert(pendingNotices, {
		string.format("Auto Return aktif (jarak deteksi %.1f stud).", state.autoTrigger),
		"info",
	})
end

-- Tulis file segera agar semua pengaturan (termasuk default) sudah ada di disk,
-- lalu simpan ulang berkala bila ada perubahan (nilai slider, dsb.).
persistSavedData()
spawnTask(function()
	while not state.closed do
		task.wait(CONFIG.AutoSaveInterval)
		if state.closed then
			return
		end
		persistSavedData()
	end
end)

spawnTask(runAutoReturnWatcher)

refreshUI()
setStatus(state.storage.available and "Siap. Data tersimpan dimuat otomatis." or "Siap. Mode sesi (tanpa penyimpanan file).", state.storage.available and "info" or "warning")
if resumeFindAfterTeleport then
	table.insert(pendingNotices, { "Find akan dilanjutkan setelah UI siap karena script rejoin otomatis.", "success" })
end
playIntro()
if resumeFindAfterTeleport then
	spawnTask(function()
		task.wait(CONFIG.IntroDuration + 0.35)
		if not state.closed then
			startFind(false)
		end
	end)
end

