<# :
@echo off
setlocal
set "BATCH_ARGS=%*"
if defined BATCH_ARGS set "BATCH_ARGS=%BATCH_ARGS:"=\"%"
if defined BATCH_ARGS set "BATCH_ARGS=%BATCH_ARGS:^^=^%"
endlocal & Powershell -NoProfile -ExecutionPolicy RemoteSigned -Command "& ([ScriptBlock]::Create((Get-Content '%~f0' | Out-String))) %BATCH_ARGS%"
pause /b
: #>

# 7-zipの実行パス（適宜修正してください）
$sevenzippath = "$env:userprofile\scoop\apps\7zip\current\7z.exe"

# ドラッグ＆ドロップされたアイテムを取得
$inputfiles = $args

if (-not $inputfiles) {
    write-host "ドラッグ＆ドロップされたファイルがありません。"
    exit
}

# cuid生成用のカウンター
$global:cuidcounter = 0

function convert-tobase36 {
    param ([long]$number)
    $chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    $result = ""
    do {
        $result = $chars[$number % 36] + $result
        $number = [math]::floor($number / 36)
    } while ($number -gt 0)
    return $result
}

# cuidを生成する関数
function new_cuid {
    # タイムスタンプをbase36に変換
    $timestamp = convert-tobase36 ([int64](([datetime]::utcnow - [datetime]'1970-01-01').totalmilliseconds))

    # カウンターをbase36に変換
    $global:cuidcounter++
    $counter = convert-tobase36 $global:cuidcounter

    # ホスト名とpidを基にハッシュ生成
    $hostname = $env:computername
    $fphash_input = "$hostname$pid"
    $fphash = (get-filehash -algorithm md5 -inputstream ([io.memorystream]::new([system.text.encoding]::utf8.getbytes($fphash_input)))).hash.substring(0, 4).tolower()

    # ランダムな文字列生成
    $rand = -join ((0..35) | get-random -count 4 | foreach-object { "0123456789abcdefghijklmnopqrstuvwxyz"[$_] })

    # cuidを生成
    $cuid = "c$timestamp$counter$fphash$rand"

    # 長さが足りない場合はランダム文字列で補完
    if ($cuid.length -lt 26) {
        $paddinglength = 26 - $cuid.length
        $cuid += -join ((0..35) | get-random -count $paddinglength | foreach-object { "0123456789abcdefghijklmnopqrstuvwxyz"[$_] })
    }

    return $cuid.substring(0, 26)  # 安全に26文字を返す
}

# ulidを生成する関数
function new_ulid {
    $timestamp = [int64](([datetime]::utcnow - [datetime]'1970-01-01').totalmilliseconds)
    $timestamp_hex = $timestamp.ToString("x8")
    $random_bytes = (1..10 | foreach-object { get-random -minimum 0 -maximum 256 })
    $random_hex = ($random_bytes | foreach-object { $_.ToString("x2") }) -join ""

    $ulid = "$timestamp_hex$random_hex"
    return $ulid.substring(0, 26)  # 必ず26文字に切り詰める
}

# 出力ファイルを元の名前＋cuid/ulidで作成
$script_root = $psscriptroot
if (-not $script_root) {
    $script_root = [system.io.directory]::getcurrentdirectory()
}

foreach ($inputfile in $inputfiles) {
    if (-not (test-path -path $inputfile)) {
        write-host "入力ファイルが見つかりません: $inputfile"
        continue
    }

    $basename = [system.io.path]::getfilenamewithoutextension($inputfile)

    # ulidかcuidを選択するフラグ
    $use_ulid = $true  # ulidを使う場合は $true、cuidを使う場合は $false に設定
    $unique_id = if ($use_ulid) { new_ulid } else { new_cuid }

    $outputfile = join-path $script_root "$basename`_$unique_id.7z"

    $command = "$sevenzippath a -t7z -mx=9 -m0=lzma2 -mmt=on -ms=on `"$outputfile`" `"$inputfile`""
    write-host "以下のコマンドを実行中："
    write-host $command
    invoke-expression $command

    write-host "圧縮が完了しました！出力ファイル：$outputfile"
}
