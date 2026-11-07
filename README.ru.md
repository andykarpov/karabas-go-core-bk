# Ядро БК-0011М + AZBK для Karabas Go / Mini / Mini G

[English version](README.md)

Домашний компьютер **Электроника БК-0011М** (К1801ВМ1, 128 КБ, БЕЙСИК и БОС в ПЗУ) с контроллером **AZBK**
(MAXIOL): диспетчер памяти на 32 МБ, 256-цветный экран 1024 x 768 с тремя слоями, блиттер, два AY, Covox,
звуковой DMA, дисковый контроллер на образах с SD-карты, EEPROM, часы; без сети. На платах семейства Karabas
Go (Xilinx Spartan-6 XC6SLX25). В работе: см. [docs/PLAN.md](docs/PLAN.md).

Один файл ядра `bk.kg` для всех плат.

| Плата | Видео | Звук |
|---|---|---|
| Karabas Go | VGA 1024 x 768 | I2S ЦАП (PCM5102) |
| Karabas Mini | HDMI 1024 x 768 | HDMI, аналоговый выход (sigma-delta) |
| Karabas Mini G | HDMI 1024 x 768 | HDMI, I2S ЦАП (PCM5102) |

## Авторы

- **Машина**: [retro-tang-bk](https://github.com/lordamot/retro-tang-bk) (BK Nano), **Сергей Лемешев** и
  соавторы, MIT ([docs/licenses/retro-tang-bk-MIT.md](docs/licenses/retro-tang-bk-MIT.md)); модель К1801ВМ1
  Vslav (1801BM1@gmail.com) в обёртке Sorgelig из ядра MiSTer BK0011M (GPL v2); YM2149 MikeJ и Sorgelig
  (BSD-подобное уведомление в файле). Поведение AZBK по эмулятору BKemu (GID) и описаниям MAXIOL на
  forum.maxiol.com.
- **Порт на Karabas** и модули плат [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules):
  Andy Karpov и соавторы.

Происхождение каждого файла: [docs/sources.md](docs/sources.md).

## Лицензия

В целом GPL-3.0-or-later, см. [LICENSE](LICENSE); каждый файл сохраняет свой заголовок. ПЗУ в `src/roms`
(ПЗУ AZBK от MAXIOL, прошивки БК-0010 / БК-0011М) это неизменённые данные их владельцев.

## Использование

Скопируйте `bk.kg` на SD-карту (SD1), образы дисков в `/bk`. Устройства AZ0..AZ3 это файловые пункты OSD;
`eeprom.dat` (настройки AZBK, 510 байт, из `soft/azbk/` retro-tang-bk) в `/bk` служит EEPROM.

Клавиши: Esc КТ, F1 ПОВТ, F2 ВС, F3 ГРАФ, F5 -!->, F6 ИНД СУ, F7 БЛОК РЕД, F8 ШАГ, F9 СБР, F10 СТОП,
F11 сброс, Alt АР2, правый Ctrl СУ, левый Ctrl РУС / ЛАТ по очереди, Caps Lock СТР; Alt+F4 (512 / 256) и Alt+левый Ctrl (палитра):
горячие клавиши AZ.

## Сборка

ISE 14.7: `cd src && make minig` (или `go`, `mini`); см. [CLAUDE.md](CLAUDE.md).
