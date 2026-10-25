# UsageBar

Claude Code ve Codex'in 5 saatlik ve haftalık limitlerini, yenilenme zamanlarını ve açık agent oturumlarını macOS menü barında gösterir.

## Çalıştırma

```bash
./scripts/bundle.sh && open build/UsageBar.app
```

`build/UsageBar.app`'i `/Applications`'a taşıyıp menüdeki "Girişte başlat" ile otomatik açılmasını sağlayabilirsiniz.

Hata ayıklama için: `swift build && .build/debug/UsageBar --dump`

## Veri kaynakları

| | Kaynak | Not |
|---|---|---|
| Claude limitleri | `api.anthropic.com/api/oauth/usage`, Claude Code'un Keychain'deki OAuth token'ı ile | 3 dakikada bir. Token yenilenmez; süresi dolarsa Claude Code'u açmak yeterli. |
| Codex limitleri | `~/.codex/sessions/**.jsonl` içindeki son `rate_limits` olayı | Codex en son çalıştığında kaydedilen değer; "son veri" olarak gösterilir. |
| Claude agent'ları | `~/.claude/sessions/<pid>.json` (çalışan süreçler, busy/idle) | 5 saniyede bir. |
| Codex agent'ları | Son 30 dk'da yazılmış oturum logları, son turun bitip bitmediği | Tahmine dayalı. |

Bunlar resmi olarak belgelenmiş API'ler değil; Claude Code veya Codex güncellemeleriyle değişebilir.
