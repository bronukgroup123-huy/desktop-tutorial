# serve.ps1 - minimal static file server for local prototype testing.
# ASCII-only on purpose (no BOM needed). Root is passed as a parameter.
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [int]$Port = 8765
)
$ErrorActionPreference = 'Stop'
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Output "Serving $Root on http://localhost:$Port/"
while ($listener.IsListening) {
    $ctx = $null
    try {
        $ctx = $listener.GetContext()
        $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
        if ($rel -eq '/') { $rel = '/mushroom-radar.html' }
        $file = Join-Path $Root ($rel.TrimStart('/').Replace('/', '\'))
        if ((Test-Path $file -PathType Leaf) -and $file.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
            $bytes = [IO.File]::ReadAllBytes($file)
            $ext = [IO.Path]::GetExtension($file).ToLower()
            $ctype = 'application/octet-stream'
            if ($ext -eq '.html') { $ctype = 'text/html; charset=utf-8' }
            elseif ($ext -eq '.json') { $ctype = 'application/json; charset=utf-8' }
            elseif ($ext -eq '.css') { $ctype = 'text/css; charset=utf-8' }
            elseif ($ext -eq '.js') { $ctype = 'text/javascript; charset=utf-8' }
            elseif ($ext -eq '.webp') { $ctype = 'image/webp' }
            elseif ($ext -eq '.png') { $ctype = 'image/png' }
            elseif ($ext -eq '.jpg' -or $ext -eq '.jpeg') { $ctype = 'image/jpeg' }
            elseif ($ext -eq '.svg') { $ctype = 'image/svg+xml' }
            $ctx.Response.StatusCode = 200
            $ctx.Response.ContentType = $ctype
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $msg = [Text.Encoding]::UTF8.GetBytes('Not found')
            $ctx.Response.StatusCode = 404
            $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
        }
    } catch {
        if ($ctx) { try { $ctx.Response.StatusCode = 500 } catch {} }
    }
    if ($ctx) { try { $ctx.Response.Close() } catch {} }
}
