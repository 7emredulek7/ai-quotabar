# Headroom

Kodlama agent'larının kullanım limitlerini, yenilenme zamanlarını ve açık agent oturumlarını macOS menü barında gösterir. Açık ve koyu modu sistemle birlikte değiştirir.

Desteklenen sağlayıcılar: **Claude Code, Codex, Cursor, GitHub Copilot, Antigravity** ve (henüz veri olmadan) **Grok**. Hangilerinin görüneceği Ayarlar'dan seçilir. İlk açılışta, kuruluysa yalnızca Claude Code ve Codex açık gelir; ikisi de yoksa kurulu olan her sağlayıcı açılır.

## Çalıştırma

```bash
./scripts/bundle.sh && open build/Headroom.app
```

`build/Headroom.app`'i `/Applications`'a taşıyıp Ayarlar'daki "Girişte başlat" ile otomatik açılmasını sağlayabilirsiniz.

Hata ayıklama için: `swift build && .build/debug/Headroom --dump`

## Veri kaynakları

| Sağlayıcı | Kaynak | Gösterilen |
|---|---|---|
| Claude Code | `api.anthropic.com/api/oauth/usage`, Claude Code'un Keychain'deki OAuth token'ı ile | 5 saatlik, haftalık |
| Codex | `~/.codex/sessions/**.jsonl` içindeki son `rate_limits` olayı | 5 saatlik, haftalık (Codex en son çalıştığındaki değer) |
| Cursor | `api2.cursor.sh` DashboardService, Cursor'un yerel `state.vscdb` dosyasındaki oturum token'ı ile | Fatura dönemi (haftalık/aylık) |
| GitHub Copilot | `api.github.com/copilot_internal/user`, `gh auth token` ile | Aylık premium istekler |
| Antigravity | Uygulama açıkken çalışan yerel language server (`GetUserStatus`) | Gemini ve Claude + GPT model kotaları |
| Grok | — | Henüz veri kaynağı yok |

Agent listesi Claude Code (`~/.claude/sessions/<pid>.json`) ve Codex (son 30 dakikada yazılmış oturum logları) için gösterilir.

Token'lar hiçbir zaman yenilenmez veya saklanmaz; yalnızca ilgili sağlayıcının kendi sunucusuna gönderilir. Uygulama ikonları çalışma anında bu Mac'te kurulu uygulamalardan okunur.

Bunlar resmi olarak belgelenmiş API'ler değil; sağlayıcıların güncellemeleriyle değişebilir.
