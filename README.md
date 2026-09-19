# eljees.github.io

Публичная страница: **https://eljees.github.io**

Портфолио публикаций и выступлений Юрия Туманова — AppSec / MLSecOps, evidence-first триаж SAST
на локальных языковых моделях.

## Устройство

Одна статическая страница без сборки и без внешних зависимостей: `index.html` содержит разметку,
стили и переключатель RU/EN. GitHub Pages отдаёт её как есть — ничего собирать и деплоить не нужно,
достаточно `git push`.

- тёмная и светлая темы через `prefers-color-scheme`, отдельного переключателя нет;
- язык переключается кнопками RU/EN, выбор запоминается в `localStorage`;
- вёрстка адаптивная, ширина колонки 760 px.

## Яндекс.Метрика

Счётчик `112396476` подключён в конце `index.html`. Включены clickmap (карта кликов),
trackLinks (учёт переходов по внешним ссылкам) и accurateTrackBounce (точный показатель отказов);
Вебвизор и ecommerce не используются — на статичной странице им нечего писать.

Авторазметка ссылок в настройках счётчика не нужна: она подставляет метки `ym_*` в переходы
из Яндекс.Директа, а рекламы здесь нет.

## Обновление

Правишь `index.html`, коммитишь, пушишь — страница обновляется за минуту-две.

```bash
git add -A && git commit -m "обновил портфолио" && git push
```

Полный реестр (включая поданные и неотобранные заявки) ведётся отдельно в репозитории
[tumanov-portfolio](https://github.com/Eljees/tumanov-portfolio).

## Где ещё

- Реестр публикаций и выступлений — https://github.com/Eljees/tumanov-portfolio
- Google Scholar — https://scholar.google.com/citations?user=iH0LwcAAAAAJ
- LinkedIn — https://www.linkedin.com/in/yury-tumanov-bb55b531/

## Презентации

Папка `slides/` — PDF-версии докладов, на них ссылается страница:

- `slides/Tumanov_ZeroFalse_ISCRA_2026.pdf` — ISCRA Talks 2026
- `slides/Tumanov_ZeroFalse_OFFZONE_2026.pdf` — OFFZONE 2026, трек AppSec.Zone
