-- common.lua - 全パーサーが共有するユーティリティ
local M = {}

local cjson_ok, cjson = pcall(require, "cjson")
M.cjson_ok = cjson_ok
M.cjson    = cjson

-- =============================================================================
-- 文字列ユーティリティ
-- =============================================================================

-- 文字列の両端の空白・改行を除去する
function M.trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

-- IPアドレス文字列をクレンジングする (例: tcp://192.168.0.249:54220 -> 192.168.0.249)
function M.clean_addr(addr)
    if not addr or addr == "" then return "" end
    -- IPv4
    local ip = addr:match("(%d+%.%d+%.%d+%.%d+)")
    if ip then return ip end
    -- IPv6 (例: tcp://[fe80::1]:54220 または fe80::1)
    local ip6 = addr:match("%[?([%x:]+:[%x:]+)%]?")
    if ip6 then return ip6 end
    -- ホスト名 (例: tcp://myhost:54220)
    local h = addr:match("^%a+://([^:]+)") or addr:match("^([^:]+):%d+$")
    if h then return h end
    return addr
end

-- =============================================================================
-- レコードフィールド取得ヘルパー
-- =============================================================================

-- Fluent Bit の tcp/udp/syslog input が "log" または "message" キーで届く生ログを返す
function M.get_raw(record)
    if not record then return "" end
    return M.trim(record["log"] or record["message"] or "")
end

-- record から接続元 IP を取得する (remote_addr -> source_address -> host の優先順)
function M.get_host_from(record)
    if not record then return "" end
    local raw_addr = record["remote_addr"] or record["source_address"] or record["host"] or ""
    return M.clean_addr(raw_addr)
end

-- =============================================================================
-- パース共通ユーティリティ
-- =============================================================================

-- key=value 形式をパースしてテーブルを返す (クォート付き・なし両対応、エスケープ引用符対応)
function M.parse_kv(str)
    if not str then return {} end
    local kv = {}
    local pos = 1
    local len = #str

    while pos <= len do
        -- key= を探す
        local k_start, k_end, k = str:find("([%w_%.%-]+)=", pos)
        if not k_start then break end

        local val_start = k_end + 1
        if val_start > len then
            kv[k] = ""
            break
        end

        -- クォート文字の判定 (直前のバックスラッシュ \" または \' で始まるケースも考慮)
        local q = nil
        local content_start = val_start
        local c1 = str:sub(val_start, val_start)
        local c2 = str:sub(val_start + 1, val_start + 1)

        if c1 == '"' or c1 == "'" then
            q = c1
            content_start = val_start + 1
        elseif c1 == "\\" and (c2 == '"' or c2 == "'") then
            q = c2
            content_start = val_start + 2
        end

        if q then
            -- クォート付き値: 終端の引用符を探す
            local val_end = nil
            local i = content_start
            while i <= len do
                local cur = str:sub(i, i)
                local nxt = str:sub(i + 1, i + 1)
                if cur == "\\" and nxt == q then
                    -- エスケープされた引用符 \" または \'
                    -- ただし、直後に空白または文字列終端がある場合は値の終端引用符（エスケープ付き）と判定
                    local after_q = str:sub(i + 2, i + 2)
                    if after_q == "" or after_q:match("%s") then
                        val_end = i
                        break
                    else
                        i = i + 2
                    end
                elseif cur == q then
                    -- 終端引用符
                    val_end = i
                    break
                else
                    i = i + 1
                end
            end

            if val_end then
                local val = str:sub(content_start, val_end - 1)
                val = val:gsub('\\"', '"'):gsub("\\'", "'")
                kv[k] = val
                pos = val_end + (str:sub(val_end, val_end) == "\\" and 2 or 1)
            else
                local val = str:sub(content_start)
                val = val:gsub('\\"', '"'):gsub("\\'", "'")
                if val:sub(-1) == q then val = val:sub(1, -2) end
                kv[k] = val
                break
            end
        else
            -- クォートなし値: 空白または文字列末尾まで
            local space_pos = str:find("%s", val_start)
            if space_pos then
                kv[k] = str:sub(val_start, space_pos - 1)
                pos = space_pos + 1
            else
                kv[k] = str:sub(val_start)
                break
            end
        end
    end

    return kv
end

-- CSV 行をパースしてフィールドの配列を返す (RFC 4180 準拠のダブルクォート対応)
function M.parse_csv(line)
    if not line then return {} end
    local res = {}
    local pos  = 1
    local len  = #line
    while pos <= len do
        if line:sub(pos, pos) == '"' then
            -- クォートされたフィールド: "" はエスケープ済み引用符
            local endp = pos + 1
            while endp <= len do
                if line:sub(endp, endp) == '"' then
                    if line:sub(endp + 1, endp + 1) == '"' then
                        endp = endp + 2   -- エスケープ済み引用符をスキップ
                    else
                        break             -- 終端引用符
                    end
                else
                    endp = endp + 1
                end
            end
            local val = line:sub(pos + 1, endp - 1):gsub('""', '"')
            table.insert(res, val)
            pos = endp + 2
        else
            -- クォートなしフィールド
            local comma = line:find(",", pos, true)
            if comma then
                table.insert(res, line:sub(pos, comma - 1))
                pos = comma + 1
            else
                table.insert(res, line:sub(pos))
                break
            end
        end
    end
    return res
end

-- 純 Lua による JSON デコーダー (cjson に依存せずオブジェクト/配列/スカラーをテーブル化)
function M.json_decode(str)
    if not str or str == "" then return nil end
    local s = M.trim(str)
    if s == "" then return nil end

    local pos = 1
    local len = #s

    local function skip_ws()
        while pos <= len and s:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local parse_value

    local function parse_string()
        if s:sub(pos, pos) ~= '"' then return nil end
        pos = pos + 1
        local res = {}
        while pos <= len do
            local c = s:sub(pos, pos)
            if c == "\\" then
                local next_c = s:sub(pos + 1, pos + 1)
                if next_c == '"' then table.insert(res, '"')
                elseif next_c == "\\" then table.insert(res, "\\")
                elseif next_c == "/" then table.insert(res, "/")
                elseif next_c == "b" then table.insert(res, "\b")
                elseif next_c == "f" then table.insert(res, "\f")
                elseif next_c == "n" then table.insert(res, "\n")
                elseif next_c == "r" then table.insert(res, "\r")
                elseif next_c == "t" then table.insert(res, "\t")
                elseif next_c == "u" then
                    -- Unicode escape (\uXXXX) 簡易対応
                    local hex = s:sub(pos + 2, pos + 5)
                    local code = tonumber(hex, 16)
                    if code and code < 128 then
                        table.insert(res, string.char(code))
                    end
                    pos = pos + 4
                else
                    table.insert(res, next_c)
                end
                pos = pos + 2
            elseif c == '"' then
                pos = pos + 1
                return table.concat(res)
            else
                table.insert(res, c)
                pos = pos + 1
            end
        end
        return table.concat(res)
    end

    local function parse_object()
        if s:sub(pos, pos) ~= "{" then return nil end
        pos = pos + 1
        local obj = {}
        skip_ws()
        if pos <= len and s:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end
        while pos <= len do
            skip_ws()
            local key = parse_string()
            if not key then break end
            skip_ws()
            if s:sub(pos, pos) ~= ":" then break end
            pos = pos + 1
            skip_ws()
            local val = parse_value()
            obj[key] = val
            skip_ws()
            local sep = s:sub(pos, pos)
            if sep == "," then
                pos = pos + 1
            elseif sep == "}" then
                pos = pos + 1
                return obj
            else
                break
            end
        end
        return obj
    end

    local function parse_array()
        if s:sub(pos, pos) ~= "[" then return nil end
        pos = pos + 1
        local arr = {}
        skip_ws()
        if pos <= len and s:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end
        while pos <= len do
            skip_ws()
            local val = parse_value()
            table.insert(arr, val)
            skip_ws()
            local sep = s:sub(pos, pos)
            if sep == "," then
                pos = pos + 1
            elseif sep == "]" then
                pos = pos + 1
                return arr
            else
                break
            end
        end
        return arr
    end

    local function parse_number()
        local num_str = s:match("^([%-%+]?%d+%.?%d*[eE]?[%-%+]?%d*)", pos)
        if num_str and num_str ~= "" and num_str ~= "-" and num_str ~= "+" then
            pos = pos + #num_str
            return tonumber(num_str)
        end
        return nil
    end

    function parse_value()
        skip_ws()
        if pos > len then return nil end
        local c = s:sub(pos, pos)
        if c == "{" then return parse_object()
        elseif c == "[" then return parse_array()
        elseif c == '"' then return parse_string()
        elseif s:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif s:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif s:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            return parse_number()
        end
    end

    skip_ws()
    return parse_value()
end

-- JSON 文字列から特定キーの値をパターンマッチで取得する (簡易代替)
function M.json_get(str, key)
    if not str or not key then return nil end
    -- 1. 通常の JSON: "key": "value"
    local v = str:match('"' .. key .. '"%s*:%s*"(.-[^\\])"')
    if v then return v end
    -- 2. エスケープされた JSON: \"key\": \"value\"
    v = str:match('\\"' .. key .. '\\"%s*:%s*\\"(.-[^\\])\\"')
    if v then return v:gsub('\\"', '"') end
    -- 3. 数値・真偽値: "key": 123
    v = str:match('"' .. key .. '"%s*:%s*([%d%.%-]+)')
    if v then return v end
    v = str:match('\\"' .. key .. '\\"%s*:%s*([%d%.%-]+)')
    if v then return v end
    return nil
end

-- 純 Lua による JSON エンコーダー (cjson に依存せずテーブルを JSON 文字列化する)
function M.json_encode(val)
    local t = type(val)
    if t == "string" then
        return string.format("%q", val):gsub("\\\n", "\\n")
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local v_str = M.json_encode(v)
            if v_str then
                table.insert(parts, string.format("%q", tostring(k)) .. ":" .. v_str)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

-- =============================================================================
-- Syslog 変換テーブル
-- =============================================================================

-- 月名 -> 2桁数字
M.month_map = {
    Jan="01", Feb="02", Mar="03", Apr="04", May="05", Jun="06",
    Jul="07", Aug="08", Sep="09", Oct="10", Nov="11", Dec="12",
}

-- Facility 番号 -> 名前
M.facility_map = {
    [0]  = "KERN",      [1]  = "USER",         [2]  = "MAIL",
    [3]  = "DAEMON",    [4]  = "AUTH",          [5]  = "SYSLOG",
    [6]  = "LPR",       [7]  = "NEWS",          [8]  = "UUCP",
    [9]  = "CRON",      [10] = "AUTHPRIV",      [11] = "FTP",
    [12] = "NTP",       [13] = "SECURITY",      [14] = "CONSOLE",
    [15] = "SOLARIS-CRON",
    [16] = "LOCAL0",    [17] = "LOCAL1",        [18] = "LOCAL2",
    [19] = "LOCAL3",    [20] = "LOCAL4",        [21] = "LOCAL5",
    [22] = "LOCAL6",    [23] = "LOCAL7",
}

-- Severity 番号 -> 名前
M.severity_map = {
    [0] = "EMERG",   [1] = "ALERT",   [2] = "CRIT",
    [3] = "ERR",     [4] = "WARNING", [5] = "NOTICE",
    [6] = "INFO",    [7] = "DEBUG",
}

-- Priority 文字列エイリアス -> 正規名
M.priority_aliases = {
    EMERG="EMERG",  EMERGENCY="EMERG",
    ALERT="ALERT",
    CRIT="CRIT",    CRITICAL="CRIT",
    ERR="ERR",      ERROR="ERR",
    WARN="WARNING", WARNING="WARNING",
    NOTICE="NOTICE",
    INFO="INFO",    INFORMATION="INFO", INFORMATIONAL="INFO",
    DEBUG="DEBUG",  TRACE="DEBUG",
}

-- Facility 番号または名前を正規名に変換する
function M.get_facility(num)
    if num == nil then return nil end
    local n = tonumber(num)
    if n and M.facility_map[n] then return M.facility_map[n] end
    return string.upper(tostring(num))
end

-- Priority 番号または文字列を正規名に変換する
function M.get_priority(val)
    if val == nil then return nil end
    local n = tonumber(val)
    if n and M.severity_map[n] then return M.severity_map[n] end
    local s = string.upper(M.trim(tostring(val)))
    return M.priority_aliases[s] or s
end

-- =============================================================================
-- 日時変換ヘルパー (マイクロ秒精度保持)
-- =============================================================================

-- コンテナ環境のタイムゾーンオフセット（秒）を起動時に一度だけ計算してキャッシュする
-- 例: TZ=Asia/Tokyo -> +32400 (9時間)
local LOCAL_TZ_OFFSET = (function()
    local now    = os.time()
    local utc_t  = os.date("!*t", now)
    local loc_t  = os.date("*t",  now)
    utc_t.isdst  = false
    loc_t.isdst  = false
    return os.difftime(os.time(loc_t), os.time(utc_t))
end)()

-- タイムゾーンオフセット（秒）を "+09:00" / "-05:00" / "Z" 形式に変換する
local LOCAL_TZ_STR = (function()
    local off = LOCAL_TZ_OFFSET
    if off == 0 then return "Z" end
    local sign    = off >= 0 and "+" or "-"
    local abs_sec = math.abs(off)
    return string.format("%s%02d:%02d", sign, math.floor(abs_sec / 3600),
                                               math.floor((abs_sec % 3600) / 60))
end)()

-- ISO 8601 文字列 (Z / ±HH:MM / TZなし) を UTC Unix epoch float に変換する
-- 例: "2026-08-22T00:14:12.693693+09:00" -> 1787372652.693693
function M.iso8601_to_unix(ts_str)
    if not ts_str or ts_str == "" then return nil end
    local y, mo, d, h, mi, s = ts_str:match("^(%d%d%d%d)[%-%/](%d%d)[%-%/](%d%d)[T%s](%d%d):(%d%d):(%d%d)")
    if not y then return nil end

    -- 小数秒 (マイクロ秒・ナノ秒等) を 0〜1 の浮動小数に変換
    local frac_str = ts_str:match("[T%s]%d%d:%d%d:%d%d%.(%d+)")
    local frac     = frac_str and (tonumber(frac_str) / (10 ^ #frac_str)) or 0.0

    -- os.time() はローカルタイムを UTC に変換するため、ローカルオフセットを加算して UTC ベースにする
    local raw_epoch = os.time({
        year  = tonumber(y),  month = tonumber(mo), day  = tonumber(d),
        hour  = tonumber(h),  min   = tonumber(mi), sec  = tonumber(s),
        isdst = false,
    })
    local utc_base = raw_epoch + LOCAL_TZ_OFFSET

    -- タイムゾーン指定に従ってオフセットを除去し UTC に揃える
    if ts_str:match("[Zz]$") then
        return utc_base + frac
    end
    local sign, tz_h, tz_m = ts_str:match("([%+%-])(%d%d):?(%d%d)$")
    if sign and tz_h then
        local offset_sec = tonumber(tz_h) * 3600 + tonumber(tz_m) * 60
        return (sign == "+" and (utc_base - offset_sec) or (utc_base + offset_sec)) + frac
    end
    -- TZなし: 設定TZのデフォルト（JST +09:00）と仮定
    return (utc_base - 9 * 3600) + frac
end

-- UTC Unix epoch float を、コンテナのタイムゾーンに従った ISO 8601 文字列に変換する
-- 例 (TZ=Asia/Tokyo): 1787372652.693693 -> "2026-08-22T13:04:12.693693+09:00"
function M.unix_to_iso8601(ts)
    if not ts then return nil end
    local sec = math.floor(ts)
    local us  = math.floor((ts - sec) * 1000000 + 0.5)
    if us >= 1000000 then sec = sec + 1; us = 0 end
    return os.date("%Y-%m-%dT%H:%M:%S", sec) .. string.format(".%06d%s", us, LOCAL_TZ_STR)
end

-- BSD / RFC 3164 の月日時刻 (例: "Aug", "22", "09:14:12.287853") を UTC Unix epoch float に変換する
-- year_str が nil の場合は現在年を使用する
-- tz_str が "UTC"/"GMT"/"Z" 以外の場合はコンテナのタイムゾーンを使用する
function M.bsd_to_unix(month_str, day_str, time_str, year_str, tz_str)
    if not month_str or not day_str or not time_str then return nil end
    local mn_key = month_str:sub(1,1):upper() .. month_str:sub(2,3):lower()
    local mo     = tonumber(M.month_map[mn_key] or month_str)
    if not mo then return nil end
    local d    = tonumber(day_str)
    local h, mi, s = time_str:match("^(%d%d):(%d%d):(%d%d)")
    if not h then return nil end
    local frac_str = time_str:match("%.(%d+)")
    local frac     = frac_str and (tonumber(frac_str) / (10 ^ #frac_str)) or 0.0
    local y        = tonumber(year_str) or tonumber(os.date("%Y"))
    local raw_epoch = os.time({
        year  = y,             month = mo, day  = d,
        hour  = tonumber(h),   min   = tonumber(mi), sec = tonumber(s),
        isdst = false,
    })
    local utc_base = raw_epoch + LOCAL_TZ_OFFSET
    if tz_str == "UTC" or tz_str == "GMT" or tz_str == "Z" then
        return utc_base + frac
    end
    -- コンテナのタイムゾーンオフセット分を除去して UTC に揃える
    return (utc_base - LOCAL_TZ_OFFSET) + frac
end

-- 数値または文字列のエポック値 (秒/ミリ秒/マイクロ秒/ナノ秒) を Unix epoch float (秒) に正規化する
function M.epoch_to_unix(val)
    if not val then return nil end
    local n = tonumber(val)
    if not n then return nil end
    if     n > 1e18 then return n / 1e9   -- ナノ秒  (19桁)
    elseif n > 1e15 then return n / 1e6   -- マイクロ秒 (16桁)
    elseif n > 1e11 then return n / 1e3   -- ミリ秒  (13桁)
    else                 return n          -- 秒
    end
end

-- =============================================================================
-- Syslog パース共通ヘルパー
-- =============================================================================

-- <pri> の数値から facility 文字列と priority 文字列を返す
-- 例: parse_syslog_pri("30") -> "DAEMON", "INFO"
function M.parse_syslog_pri(pri_str)
    local p = tonumber(pri_str) or 0
    return M.get_facility(math.floor(p / 8)), M.get_priority(p % 8)
end

-- out["host_from"] が空または nil の場合に out["host"] の値で補完する
function M.normalize_host_from(out)
    if (not out["host_from"] or out["host_from"] == "") and
       out["host"] and out["host"] ~= "" then
        out["host_from"] = out["host"]
    end
end

-- YAMAHA RTX 等の [TAG] 形式ホストフィールドを補正する
--   h        : パースされた host 位置の文字列 (例: "[PPPoE]")
--   msg      : 現在のメッセージ本文
--   host_from: 接続元 IP
--   out      : 出力レコード (host / program を上書き)
--   戻り値   : 補正後の msg
function M.extract_yamaha_tag(h, msg, host_from, out)
    if h and h:sub(1, 1) == "[" and h:sub(-1) == "]" then
        -- ホストフィールドが [TAG] 形式の場合: host_from を host に昇格し TAG を program に設定
        out["program"] = h:match("%[([^%]]+)%]")
        out["host"]    = (host_from and host_from ~= "") and host_from or nil
        return h .. (msg and (" " .. msg) or "")
    else
        out["host"] = h or (host_from ~= "" and host_from or nil)
        return msg
    end
end

-- =============================================================================
-- RFC 5424 パーサー
-- =============================================================================
-- 成功時: { pri, facility, priority, ts, host, program, pid, msgid,
--           structured_data, message, gen_ts, parse_type } を返す
-- 失敗時: nil を返す
function M.parse_rfc5424(raw)
    if not raw or raw == "" then return nil end

    -- 先頭に TCP オクテットカウント（例: "132 <86>1..."）が付いている場合は読み飛ばす
    local text = raw:match("^%d+%s+(<[0-9]+>.*)") or raw

    -- 構造化データあり
    local pri, ver, ts, host, prog, pid, msgid, sd, msg =
        text:match("^<([0-9]+)>([0-9]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +(%S+) ?(.*)")
    -- 構造化データなし
    if not msg then
        pri, ver, ts, host, prog, pid, msgid, msg =
            text:match("^<([0-9]+)>([0-9]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +([^ ]+) +(.*)")
    end
    if not (pri and ver and tonumber(ver)) then return nil end

    local fac, severity = M.parse_syslog_pri(pri)

    -- "-" はフィールド欠落を意味するため nil に変換する
    local function nil_if_dash(v) return (v and v ~= "-") and v or nil end

    return {
        pri             = pri,
        facility        = fac,
        priority        = severity,
        ts              = ts,
        host            = nil_if_dash(host),
        program         = nil_if_dash(prog),
        pid             = nil_if_dash(pid),
        msgid           = nil_if_dash(msgid),
        structured_data = (sd and sd ~= "-" and sd ~= "") and sd or nil,
        message         = msg,
        gen_ts          = M.iso8601_to_unix(ts),
        parse_type      = "RFC5424",
    }
end

-- =============================================================================
-- RFC 3164 / YAMAHA RTX / IX ルーター パーサー
-- =============================================================================
-- 成功時: { pri, facility, priority, month, day, time_part,
--           host, program, pid, message, gen_ts, is_yamaha_date,
--           yr_yamaha, mo_yamaha, da_yamaha, tp_yamaha, parse_type } を返す
-- 失敗時: nil を返す
function M.parse_rfc3164(raw)
    if not raw or raw == "" then return nil end

    -- 先頭に TCP オクテットカウントが付いている場合は読み飛ばす
    local text = raw:match("^%d+%s+(<[0-9]+>.*)") or raw

    local pri, month, day, time_part, host, prog, pid, msg
    local p_type, is_yamaha_date, is_bsd_no_pri = nil, false, false
    local yr_yamaha, mo_yamaha, da_yamaha, tp_yamaha

    -- パターン 1: <pri> Mon DD HH:MM:SS host program[pid]: message
    pri, month, day, time_part, host, prog, pid, msg =
        text:match("^<([0-9]+)>%s*([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+)%s+([^%s:]+)%s+([^%s%[:]+)%s*%[([0-9]+)%]:%s*(.*)")
    if msg then p_type = "RFC3164_PRI_Host_Prog_PID" end

    -- パターン 2: <pri> Mon DD HH:MM:SS host program: message
    if not msg then
        pri, month, day, time_part, host, prog, msg =
            raw:match("^<([0-9]+)>%s*([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+)%s+([^%s:]+)%s+([^%s%[:]+):%s*(.*)")
        if msg then p_type = "RFC3164_PRI_Host_Prog" end
    end

    -- パターン 3: <pri> Mon DD HH:MM:SS host message
    if not msg then
        pri, month, day, time_part, host, msg =
            raw:match("^<([0-9]+)>%s*([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+)%s+([^%s:]+)%s+(.*)")
        if msg then p_type = "RFC3164_PRI_Host" end
    end

    -- パターン 4: <pri> Mon DD HH:MM:SS message (ホスト名なし)
    if not msg then
        pri, month, day, time_part, msg =
            raw:match("^<([0-9]+)>%s*([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+)%s+(.*)")
        if msg then p_type = "RFC3164_PRI" end
    end

    -- パターン 5: <pri> YYYY/MM/DD HH:MM:SS message (YAMAHA 日付形式)
    if not msg then
        local ypri, yr, mo, da, tp, rest =
            raw:match("^<([0-9]+)>%s*(%d%d%d%d)[/%-](%d%d)[/%-](%d%d)%s+([0-9:.]+)%s+(.*)")
        if ypri then
            pri = ypri
            yr_yamaha, mo_yamaha, da_yamaha, tp_yamaha = yr, mo, da, tp
            msg             = rest
            is_yamaha_date  = true
        end
    end

    -- パターン 6: Mon DD HH:MM:SS host program[pid]: message (<pri> なし BSD 形式)
    if not msg then
        month, day, time_part, host, prog, pid, msg =
            raw:match("^([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+)%s+([^%s:]+)%s+([^%s%[:]+)%s*%[([0-9]+)%]:%s*(.*)")
        if not msg then
            month, day, time_part, host, prog, msg =
                raw:match("^([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+)%s+([^%s:]+)%s+([^%s%[:]+):%s*(.*)")
        end
        if not msg then
            month, day, time_part, host, msg =
                raw:match("^([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+)%s+([^%s:]+)%s+(.*)")
        end
        if msg then is_bsd_no_pri = true end
    end

    if not msg then return nil end

    local fac, severity = nil, nil
    if pri then fac, severity = M.parse_syslog_pri(pri) end

    -- タイムスタンプ計算と parse_type の決定
    local gen_ts
    if is_yamaha_date then
        gen_ts = M.iso8601_to_unix(
            string.format("%s-%s-%sT%s+09:00", yr_yamaha, mo_yamaha, da_yamaha, tp_yamaha))
        p_type = "YAMAHA"
    elseif is_bsd_no_pri or (month and day and time_part) then
        gen_ts = M.bsd_to_unix(month, day, time_part)
        p_type = is_bsd_no_pri and "BSD" or (p_type or "RFC3164")
    end

    return {
        pri            = pri,
        facility       = fac,
        priority       = severity,
        month          = month,
        day            = day,
        time_part      = time_part,
        host           = host,
        program        = prog,
        pid            = pid,
        message        = msg,
        gen_ts         = gen_ts,
        is_yamaha_date = is_yamaha_date,
        yr_yamaha      = yr_yamaha,
        mo_yamaha      = mo_yamaha,
        da_yamaha      = da_yamaha,
        tp_yamaha      = tp_yamaha,
        parse_type     = p_type,
    }
end

-- =============================================================================
-- 基本レコード作成ヘルパー
-- =============================================================================

-- 各パーサーの共通基盤となる out レコードを生成する
-- source フィールドに port と transport を統合する (例: "s_fluent_bit/6514/tcp")
-- 戻り値: out, raw, host_from, port, transport
function M.create_base_record(tag, timestamp, record, default_port, source_name)
    local raw        = M.get_raw(record)
    local remote_addr = M.clean_addr(record["remote_addr"] or record["source_address"] or "")
    local host_from  = remote_addr ~= "" and remote_addr or M.get_host_from(record)
    local is_tcp     = tag:find("%.tcp") ~= nil
    local transport  = is_tcp and "tcp" or "udp"
    local port       = tag:find("%.octet") and 2514 or default_port
    local source     = string.format("%s/%d/%s", source_name, port, transport)

    local out = {
        host        = host_from,
        host_from   = host_from,
        source      = source,
        raw_message = raw,
        message     = raw,
        priority    = "INFO",
        received_at = M.unix_to_iso8601(timestamp),
        parse_type  = "RAW_FALLBACK",
    }
    return out, raw, host_from, port, transport
end

return M
