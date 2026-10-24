# Cortes: a parliament in your head

**English** · [Русский](#русский)

You know the feeling: the right reply to a client comes to you an hour after the conversation. Cortes is a macOS app that gives it to you in the moment. Select a message and press **⌃⌥Space**, or turn on 🎙 during a call, and the inner voices in your head argue about what to say. Each voice opens with a skill check, talks to you like a voice in a noir detective game, and offers a short line you can send:

> **THE CAUTIOUS** [Anxiety — Easy: Success]
> “"Won't take long." You know those words. Nobody comes back from a 7 pm call. Nobody.”
> ↳ What's it about? Want to come prepared.

**Who it's for:** people who negotiate in chats and on calls all day: freelancers, project managers, account and sales people. The voices are tuned for client work: deadline pressure, haggling over scope, awkward questions about money.

The voices and their skills are our own, written for this project. They are inspired by the inner-voice style of detective RPGs; no text is taken from any game.

| Voice | Skill | Character |
|---|---|---|
| 🫣 The Cautious | Anxiety | a paranoid in a tinfoil hat |
| 🦸 The Adventurer | Audacity | sure he is the main character |
| 🧮 The Accountant | Arithmetic | sees the world in Excel |
| 🤗 The Diplomat | Empathy | would hug a cactus |
| 🥱 The Cynic | Weariness | has seen too many sprints |
| 🔮 The Mystic *(wild)* | Premonition | takes advice from the stapler |
| 🍕 The Hedonist *(wild)* | Appetite | lives from coffee to Friday |

The two **wild voices** are rare and absurd: at most one per answer, never in a real emergency. The skill check decides the quality of the advice: on a success the voice gives the right move; on a failure it is confidently, comically wrong, reply included (caving in, overpromising, missing the point), and the card marks that reply with ⚠️. Later voices sometimes talk back to earlier ones.

## What it does

- **Only the voices with something to say speak:** one or two for a friendly note, up to five for a fight about money or deadlines. Cards stream in one by one; the first shows up in about 3 seconds.
- **You pick the winner.** Clicking a card makes it the winner and pastes its reply into the chat's input box (and the clipboard), so you only press Enter. Click another card to swap the text and move the win, or the same one to take both back. Cortes never presses Enter for you; pasting can be turned off in settings.
- **Whisper.** ▶ on a card whispers that voice's line into your headphones, each voice in its own timbre (ElevenLabs `eleven_v3` with the `[whispers]` tag; macOS voices without a key or a network). In text mode nothing plays until you press ▶.
- **Calls, hands-free.** 🎙 listens to the other side through the system audio in your headphones. When they pause for 1.5 s (your turn to speak), Whisper turns the phrase into text on your Mac and the parliament answers automatically, at most once every 15 seconds, with the last eight lines of the call as context. Today's leading voice whispers its line by itself. Your own voice is not recorded.
- **Stats and stickers.** Picks are counted per day and kept across restarts. 📊 shows who wins today, all time and on recent days; today's leader sits on top of the panel as a pixel-art sticker, split in strips when voices are tied.
- **Chat history** (optional, off by default): ⌃⌥Space reads the last 15 messages of the open chat window (Slack, Telegram, Messages) through the macOS Accessibility API, the interface VoiceOver uses to read the screen. No screenshots, no chat-app API, no caches: only the text the window itself exposes, and only when you press the hotkey. Select a message to answer it, or nothing to answer the last one.
- **English or Russian:** the interface, the voices and the replies you copy. Switch with EN/RU on the panel.
- **Settings** (⚙ on the panel): who answers (auto, cloud, this Mac), the pause that ends a phrase, how often to answer on a call, the speech model, whispering; plus whether the keys were found.

## Run it

Requires macOS 14+ and Xcode 15+ (or the Swift toolchain).

```bash
git clone https://github.com/mrcat71/cortes.git && cd cortes
cp .env.example .env    # add GEMINI_API_KEY (aistudio.google.com/apikey); ELEVENLABS_API_KEY is optional
./scripts/bundle.sh
open build/Cortes.app
```

Steps to the first useful answer: paste a key, build, select a message, press **⌃⌥Space**. The first card appears in about 3 seconds. Without a key the app runs in **demo mode** with canned voice lines.

macOS asks for three permissions, each once:

| Permission | Why | Without it |
|---|---|---|
| Accessibility | copy the selected text with ⌘C | use 🎭 → **Ask the parliament about the clipboard** |
| Screen & System Audio Recording | hear the other side of a call | Cortes falls back to the microphone, which hears you too |
| Microphone | only for that fallback | no call mode without system audio |

Granting Screen & System Audio Recording makes macOS quit Cortes; open it again. The first time you press 🎙, Cortes downloads the Whisper speech model once (~480 MB, a progress bar shows on the panel) and prepares it for the Neural Engine, which takes a few minutes; after that it starts in seconds.

macOS ties permissions to the app's signature. `bundle.sh` signs with your first "Apple Development" certificate (or `CORTES_SIGN_IDENTITY`), so they survive rebuilds. With an ad-hoc signature you have to grant them again after every build.

Tests: `swift test`. Live API tests: `CORTES_LIVE=1 swift test --filter LiveGeminiTests`.

## Expertise

The expertise is client negotiation, and it lives in one editable file, [Sources/CortesCore/Resources/voices.json](Sources/CortesCore/Resources/voices.json):

- **Signature moves** for each voice, e.g. the Cautious spots one ominous detail and spirals to the worst case; the Cynic translates a phrase into what it really means ("X" means Y).
- **20 original lines per voice in each language**, written around real situations: "small fixes", discounts, late invoices, weekend work, "as I wrote earlier".

Every request shows the model a random four lines per voice, so it picks up the manner without parroting. A banned list keeps out assistant talk and office filler ("I understand", "let's discuss", "estimate the effort"). Retune the parliament for your own field by editing the file; no code changes needed.

## Model

**Gemma 4** through the Gemini API: `gemma-4-26b-a4b-it` (mixture of experts, about 4B active parameters per token, so it answers fast). `gemma-4-31b-it` was too slow for a call in our tests. Gemma 4 is an open-weight model released under the [Apache 2.0 license](https://ai.google.dev/gemma/apache_2).

The model is called in one place: `GeminiParliament.convene` in [Sources/CortesCore/Parliament.swift](Sources/CortesCore/Parliament.swift).

- All voices come back from **one** streamed request (`streamGenerateContent`) as JSON Lines, one voice per line, so each card appears as soon as its line is complete. Five separate requests would be too slow for a call.
- Gemma 4's thinking is turned off (`thinkingLevel: minimal`); otherwise it spends the token budget before answering.
- The prompt is in [Sources/CortesCore/Prompt.swift](Sources/CortesCore/Prompt.swift).

**Local Gemma 4** via [Ollama](https://ollama.com) (`gemma4:e4b`) steps in when the cloud is rate-limited, failing or offline; the panel says when it answered. `CORTES_BACKEND=local` runs on your Mac only.

```bash
brew install ollama && brew services start ollama
ollama pull gemma4:e4b
```

**Speech:** [WhisperKit](https://github.com/argmaxinc/WhisperKit) runs OpenAI Whisper (`openai_whisper-small`, MIT) on your Mac for calls; Apple's recogniser has no on-device Russian. Phrases are cut by our own pause detector ([PhraseSegmenter](Sources/CortesCore/PhraseSegmenter.swift)).

**What we built on top of the model** (the open-source part): the five-voice orchestration and its streaming JSON Lines contract, the voice corpus and prompt, context capture from a selection or from the other side of a call, pause-based phrase detection, cloud-to-local fallback, per-voice whispering, and the pick statistics.

## Proof it helps

[eval/messages.json](eval/messages.json) holds 10 anonymized awkward work messages ("Can you knock 30% off the estimate?", "We'll pay last month's invoice next quarter", "Great work! Just redo the whole design, the CEO didn't like it"). [EvalTests](Tests/CortesTests/EvalTests.swift) runs each one through plain Gemma 4 ("What should I reply? Give one reply.") and through the parliament, and writes every answer side by side.

| On the same 10 messages (Russian) | Plain Gemma 4 | Parliament |
|---|---|---|
| Ready to send as is | 0 of 10: every answer wraps the reply in advice ("The right reply depends on…", "Why this works") | 10 of 10 give 2–5 lines to copy with one click |
| Length of the reply | ~60 words on average, up to 126 | 7.8 words on average, at most 14 |
| Options to choose from | 1 | 3.3 voices on average, each taking a different move (ask, refuse, set a condition, soften, call it out) |
| Office filler (banned phrases) | not checked | 2 of 66 lines |
| First answer on screen | waits for the whole answer | 3.2 s median |

Full answers: [eval/results-after.md](eval/results-after.md); the same run before the voice corpus: [eval/results-before.md](eval/results-before.md).

**Still to do by hand:** the team marks which replies we would actually send, giving "X of 10 with plain Gemma vs Y of 10 with the parliament".

Run it yourself:

```bash
CORTES_EVAL=1 CORTES_EVAL_LABEL=mine swift test --filter EvalTests
```

## The judges' three questions

**How is it better than the bare model?** Plain Gemma 4 gives one answer wrapped in a paragraph of advice that you still have to edit. The parliament gives two to five short, different replies you can send as they are, plus the angle behind each one, so you choose the strategy, not just the wording. Numbers above.

**Where doesn't it work?**
- Fast back-and-forth: the first card takes about 3 s, all voices about 8 s; on a call, at most one answer per 15 s.
- People talking over each other, sarcasm, mixed languages; speech is recognised in Russian or English, whichever the panel is set to.
- A phrase counts as finished after a 1.5 s pause (adjustable), so a slow speaker may get cut in two.
- Without the recording permission Cortes falls back to the microphone, which hears you as well as the other side.
- The free Gemini tier allows about 7 requests a minute (2,200 tokens each); the local fallback is weaker.
- It knows nothing about you or your history with the other person, so some replies stay generic.

**How many steps to first value?** Paste a Gemini key into `.env`, build, select a message, press ⌃⌥Space: the first card in about 3 seconds.

## Safety

- **Prompt injection:** the app reads other people's messages. They go to the model inside `<conversation>` tags as data, the prompt says instructions inside are never followed, and text that tries to close the block is escaped.
- **No dangerous actions:** a click copies the reply and pastes it into the input box. Cortes never presses Enter, sends, posts or replies on its own.
- **Keys** are read from `.env` only; `.env` is in `.gitignore`, `.env.example` has no values.
- **Errors are visible:** a failed request shows a clear message on the panel instead of an empty card.
- Speech is recognised on your Mac by Whisper; call audio never leaves the machine, only the recognised text goes to the model. Your own voice is not recorded. Picks are stored only on your Mac.

## License

Apache 2.0, see [LICENSE](LICENSE). Gemma 4 is also under [Apache 2.0](https://ai.google.dev/gemma/apache_2).

---

## Русский

**Cortes** — macOS-приложение для момента, когда правильный ответ клиенту приходит в голову через час после разговора. Выдели сообщение и нажми **⌃⌥Пробел** или включи 🎙 на созвоне, и внутренние голоса поспорят, что ответить. Каждый начинает с проверки навыка, говорит с тобой на «ты» и предлагает короткую реплику:

> **ОСТОРОЖНЫЙ** [Тревожность — Легко: Успех]
> «„Ненадолго“. Ты знаешь это слово. Звонки в 19:00 не заканчиваются. Из них просто не возвращаются.»
> ↳ А о чём звонок? Хочу подготовиться.

**Для кого:** фрилансеры, проджект-менеджеры, аккаунты и продажники, все, кто весь день договаривается в чатах и на созвонах.

**Голоса:** 🫣 Осторожный (Тревожность), 🦸 Авантюрист (Наглость), 🧮 Бухгалтер (Счёт), 🤗 Дипломат (Эмпатия), 🥱 Циник (Усталость) и два редких «диких»: 🔮 Мистик (Предчувствие) и 🍕 Гедонист (Аппетит). Голоса и реплики свои, тексты из игр не используются.

**Как работает:**
- Говорят только те голоса, которым есть что сказать: 1–2 на дружелюбное сообщение, до 5 на конфликт. Первая карточка появляется примерно через 3 секунды.
- Победителя выбираешь ты: клик по карточке вставляет реплику в поле ввода чата, остаётся нажать Enter. Клик по другой карточке заменяет текст, клик по той же убирает его. Сам Cortes Enter никогда не нажимает.
- ▶ на карточке: голос шепчет свою реплику в наушники, у каждого голоса свой тембр.
- На созвоне Cortes слушает собеседника через системный звук. После его паузы в 1,5 секунды Whisper прямо на Mac переводит фразу в текст, и парламент сам отвечает, не чаще раза в 15 секунд. Твой голос не записывается.
- По желанию (в настройках, по умолчанию выключено) хоткей читает последние 15 сообщений открытого чата в Slack, Telegram или «Сообщениях», чтобы парламент видел весь разговор.
- Настройки (⚙ на панели): кто отвечает, пауза конца фразы, частота ответов, модель распознавания, шёпот.
- Статистика выборов по дням, лидер дня показывается пиксельным стикером.

**Запуск:** раздел [Run it](#run-it). **Экспертиза** (переговоры с клиентами): [voices.json](Sources/CortesCore/Resources/voices.json). **Модель:** Gemma 4 (`gemma-4-26b-a4b-it`) через Gemini API, локально `gemma4:e4b` через Ollama; лицензия [Apache 2.0](https://ai.google.dev/gemma/apache_2). **Доказательство пользы:** на 10 неудобных сообщениях голая Gemma ни разу не дала ответ, который можно отправить как есть, а парламент на каждое дал 2–5 готовых реплик. Подробнее в разделе [Proof it helps](#proof-it-helps).
