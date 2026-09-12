-- cef.lua - Port 999: CEF (Common Event Format) ログパーサー
-- フォーマット: CEF:version|vendor|product|version|class_id|name|severity|extension
package.path = package.path .. ";/fluent-bit/scripts/?.lua"
local common = require("common")

function process(tag, timestamp, record)
    local out, raw, host_from, port, transport =
        common.create_base_record(tag, timestamp, record, 999, "s_cef")

    if raw == "" then return 1, timestamp, out end
    out["raw_message"] = raw

    -- CEF ヘッダーの解析 (パイプ区切り 8フィールド)
    local ver, vendor, prod, dver, cls, name, sev, ext =
        raw:match("CEF:([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|?(.*)")

    if not ver then
        out["parse_type"] = "CEF_FALLBACK"
        return 1, timestamp, out
    end

    -- 共通フィールドの設定
    out["cef_version"]           = common.trim(ver)
    out["device_vendor"]         = common.trim(vendor)
    out["device_product"]        = common.trim(prod)
    out["device_version"]        = common.trim(dver)
    out["device_event_class_id"] = common.trim(cls)
    out["name"]                  = common.trim(name)
    out["priority"]              = common.get_priority(common.trim(sev))
    out["program"]               = common.trim(vendor) .. "/" .. common.trim(prod)
    out["message"]               = common.trim(name)

    -- 拡張フィールド (Extension) のパース
    local gen_ts
    if ext and ext ~= "" then
        local kv = common.parse_kv(ext)
        for k, v in pairs(kv) do
            out["_cef." .. k] = v
        end
        -- msg フィールドがあれば message を上書き
        if kv["msg"] then out["message"] = kv["msg"] end
        -- rt / agentRt: エポックミリ秒 -> Unix epoch float
        local rt = kv["agentRt"] or kv["rt"]
        if rt then gen_ts = common.epoch_to_unix(rt) end
    end

    out["parse_type"] = "CEF"
    return 1, (gen_ts or timestamp), out
end
