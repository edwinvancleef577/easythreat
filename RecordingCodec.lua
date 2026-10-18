local E=EasyThreat
-- Adler-32 detects accidental transport corruption. Sender identity is checked
-- separately against the current party; this checksum is not authentication.
function E:RecordingChecksum(text)
    local a,b=1,0
    for i=1,string.len(text) do a=math.mod(a+string.byte(text,i),65521); b=math.mod(b+a,65521) end
    return b*65536+a
end
function E:RecordingPseudonym(guid,session)
    local text=session..":"..guid; local hash=5381
    for i=1,string.len(text) do hash=math.mod(hash*33+string.byte(text,i),4294967291) end
    return string.format("U%08x",hash)
end
-- Bounded 12-bit LZW, represented by two printable base64 digits per code.
-- No dependency, executable serialization or binary addon-message payloads.
function E:PackRecording(text)
    local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local dictionary,nextCode,out={},257,{}
    local function reset()
        dictionary={}; for i=0,255 do dictionary[string.char(i)]=i end
        nextCode=257
    end
    local function emit(code)
        local a=math.floor(code/64)+1; local b=math.mod(code,64)+1
        table.insert(out,string.sub(alphabet,a,a)..string.sub(alphabet,b,b))
    end
    reset(); local word=""
    for i=1,string.len(text) do
        local byte=string.sub(text,i,i); local combined=word..byte
        if dictionary[combined] then word=combined
        else
            emit(dictionary[word])
            if nextCode<4096 then dictionary[combined]=nextCode; nextCode=nextCode+1
            else emit(256); reset() end
            word=byte
        end
    end
    if word~="" then emit(dictionary[word]) end
    return table.concat(out)
end
