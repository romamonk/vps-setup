# vps-setup

Воспроизводимая настройка VPS для удалённой разработки через SSH и tmux,
работы Claude Code и вспомогательных сервисов.

## Реализация

Реализованы Ansible playbooks для Ubuntu 24.04: пользователи, SSH, UFW,
обновления безопасности, fail2ban, CLI-инструменты, tmux и Claude Code.
Первый запуск и hardening разделены: доступ проверяется перед ограничением SSH.
Техническое задание: [VPS_CLAUDE_CODE_BOOTSTRAP_SPEC.md](VPS_CLAUDE_CODE_BOOTSTRAP_SPEC.md).

Docker пока не реализован и не устанавливается. Go, Python venv/pip и Node.js
опциональны: используются пакеты Ubuntu, без обещания последних upstream-версий.
`admin` получает sudo (по умолчанию без пароля), `agent` не получает sudo или
доступа к системному Docker. Поддерживается существующий SSH-порт; миграцию
порта, в том числе при socket activation Ubuntu, этот шаблон не выполняет.

## Установка Ansible на управляющем компьютере

Нужны Python 3.14+ и OpenSSH. Из корня проекта:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/ansible-galaxy collection install -r requirements.yml
make lint syntax
```

Если публичный Galaxy не открывается из-за прав локального `.netrc`, можно
запустить команду установки collections с `NETRC=/dev/null`, без его credentials.

## Структура

- `playbooks/bootstrap.yml` — создание пользователей через исходный доступ.
- `playbooks/configure.yml` — окружение и автоматические security updates.
- `playbooks/harden.yml` — проверка нового доступа, SSH hardening и UFW.
- `playbooks/verify.yml` — проверки фактического состояния.
- `playbooks/reboot.yml` — отдельная перезагрузка, если ОС требует её.
- `tasks/` — общие проверки и установка Claude Code.
- `inventories/example/` — параметры без персональных данных.
- `inventories/local/` — локальный inventory, исключённый из Git.
- `templates/ssh_config.example` — клиентские SSH aliases.
- `.github/workflows/check.yml` — lint и syntax checks без доступа к VPS.

## Подготовка inventory

```sh
cp -R inventories/example inventories/local
```

Заполнить адрес VPS, исходного SSH-пользователя, публичные SSH-ключи и разрешённые
CIDR в локальной копии. Пример намеренно содержит незаполненные значения.
Private keys, токены и пароли в inventory не добавлять.
Путь к inventory передавать явно через `-i inventories/local/hosts.yml`.

## Первый запуск

1. Проверьте recovery/web-консоль провайдера. В локальном inventory задайте адрес,
   исходного пользователя root либо пользователя с sudo, SSH-порт и
   `recovery_access_confirmed: true` только после фактической проверки консоли.
2. Найдите публичные ключи командой `ls ~/.ssh/*.pub`. При нескольких ключах
   выберите нужный; другой путь также допустим. Не перезаписывайте существующие
   ключи. Если ключей нет, создание нового — отдельное решение владельца.
3. Заполните `admin_authorized_keys` и `agent_authorized_keys` содержимым выбранных
   `.pub` файлов. Можно использовать один ключ для обоих пользователей.
   `admin_private_key_file` и `agent_private_key_file` задают локальные пути
   для проверки доступа. Приватные ключи остаются на управляющем компьютере.
4. Явно задайте `ssh_allowed_cidrs`. Для публичного SSH по решению владельца:
   `['0.0.0.0/0', '::/0']`. Пустой список запрещает hardening. Для ограниченного
   доступа включите текущий адрес клиента и учтите его возможную смену.
   `public_tcp_ports: []` не открывает дополнительных портов.
5. Проверьте SSH host fingerprint по доверенному каналу провайдера, войдите
   обычным `ssh` и сохраните исходную сессию открытой до окончания проверок.
   Сначала создайте пользователей через исходные учётные данные:

```sh
.venv/bin/ansible-playbook -i inventories/local/hosts.yml playbooks/bootstrap.yml
```

Для исходного SSH-входа по паролю добавьте `--ask-pass`; если исходному
пользователю нужен sudo-пароль, также `--ask-become-pass`. Вводите пароли
интерактивно в локальном терминале, без записи в inventory, чат или аргументы.
Если ключ зашифрован passphrase, предварительно загрузите его в `ssh-agent`.
Проверки используют `BatchMode=yes` и отдельные соединения без multiplexing.

`admin_passwordless_sudo: true` создаёт правило NOPASSWD только для `admin`.
При выборе `false` заранее обеспечьте ему работающий локальный пароль через
интерактивный `passwd` и используйте `--ask-become-pass`. Шаблон пароли не задаёт.

После успешного bootstrap измените `ansible_user` в локальном inventory на
выбранного `admin`, задайте `ansible_ssh_private_key_file` при нестандартном пути
и проверьте `ssh admin@<VPS> 'sudo -n id -u'` (ожидается `0` для NOPASSWD).
Далее:

```sh
.venv/bin/ansible-playbook -i inventories/local/hosts.yml playbooks/configure.yml
.venv/bin/ansible-playbook -i inventories/local/hosts.yml playbooks/harden.yml
.venv/bin/ansible-playbook -i inventories/local/hosts.yml playbooks/verify.yml
```

Hardening требует входа через `admin` и рабочего sudo, заново проверяет оба
ключевых входа, проверяет `sshd -t` и эффективные значения с контекстом `Match`.
Управляемый drop-in подключается в начале `sshd_config`, перед cloud-init.
После reload проверка входов повторяется, затем добавляются правила SSH и
включается UFW. При сбое SSH-блока восстанавливается исходная конфигурация.
Не закрывайте исходную сессию до успешных проверок, включая проверку после UFW.

Повторные прогоны всех playbooks выполняются через `admin`, без исходного
пароля провайдера. Изменения CIDR/портов не удаляют старые UFW-правила автоматически:
перед сужением политики проверьте и удалите устаревшие разрешения отдельно.
Существующие authorized keys сохраняются; отзыв ключей выполняется явно.

## Claude Code и tmux

Установщик скачивается с официального HTTPS URL отдельно, проверяется SHA256,
запускается под `agent`, устанавливает канал `stable` и проверяет checksum бинарника.
Проверенный SHA256 задан в inventory; если upstream изменит скрипт, установка
остановится. Перед обновлением SHA256 нужно заново прочитать установщик.
Повторный прогон не переустанавливает существующий launcher; native Claude
обновляется самостоятельно. Автозапуск и обход permission prompts не включены.

Заполните aliases по `templates/ssh_config.example`, затем:

```sh
ssh -t vps-agent 'tmux new-session -A -s claude'
```

Внутри сессии:

```sh
cd ~/workspace
claude
```

Первую авторизацию Claude выполняет владелец интерактивно по подсказкам CLI
(подписка или API). Токены не передавать в Ansible или Git. Detach: `Ctrl+B`,
затем `D`; повторное подключение той же командой. tmux переживает разрыв SSH,
но не reboot. После reboot создайте сессию заново и возобновите задачу вручную.

## Проверки и восстановление

- `make lint syntax` — проверки шаблона локально и в CI.
- `playbooks/verify.yml` — ключевые подключения, SSH/UFW, права `agent`,
  APT, fail2ban и версия Claude; повторный прогон — проверка идемпотентности.
- `sudo ss -lntup`, `sudo ufw status verbose`, внешний скан — сверка портов.
- `df -h`, `free -h`, `apt list --upgradable`,
  `test -f /var/run/reboot-required` — диагностика и необходимость reboot.

При потере доступа используйте открытую исходную SSH-сессию либо консоль
провайдера. Проверьте `sshd -t`, `journalctl -u ssh`, правила `ufw status numbered`.
Восстановите разрешение текущего адреса на SSH-порт. При аварийном откате SSH
удалите `/etc/ssh/sshd_config.d/00-vps-setup.conf`, восстановите
`/etc/ssh/sshd_config` из `/etc/ssh/sshd_config.before-vps-setup`, выполните
`sshd -t` и только после успеха `systemctl reload ssh`. Это возвращает исходную
политику, включая возможный парольный/root-вход; после восстановления исправьте
inventory и повторите hardening. При необходимости временно выключите UFW
из консоли, затем верните защиту после исправления правил.

Автоматические обновления не перезагружают VPS. Reboot планируется после
сохранения работы и проверки административного доступа. Для согласованного окна:

```sh
.venv/bin/ansible-playbook -i inventories/local/hosts.yml playbooks/reboot.yml
.venv/bin/ansible-playbook -i inventories/local/hosts.yml playbooks/configure.yml
.venv/bin/ansible-playbook -i inventories/local/hosts.yml playbooks/verify.yml
```

`configure.yml` создаёт пустую сессию tmux `claude` под `agent`, если её нет;
сам Claude автоматически не запускается. Проекты регулярно
пушить в удалённый Git; незакоммиченные файлы и данные сервисов требуют отдельного
backup вне VPS. Шаблон пока не настраивает внешнее резервное копирование.

## Проверенные официальные источники

- [Ansible: установка](https://docs.ansible.com/projects/ansible/latest/installation_guide/intro_installation.html)
- [Claude Code: native installation](https://code.claude.com/docs/en/setup)
- [Ubuntu: automatic updates](https://ubuntu.com/server/docs/how-to/software/automatic-updates/)
- [Ansible: UFW](https://docs.ansible.com/projects/ansible/latest/collections/community/general/ufw_module.html)

## Ограничения

Аккаунт `agent`, tmux и Git worktrees не обеспечивают изоляцию проектов и секретов.
Permission rules Claude не заменяют OS sandbox. tmux сохраняет процессы при
разрыве SSH, но не после перезагрузки. Полностью автономная работа не гарантируется.
Docker-порты требуют отдельной проверки доступности извне: одного UFW недостаточно.
Production-секреты и критичная production-инфраструктура вне scope MVP.

## Git remote

Адрес репозитория: `git@github.com:romamonk/vps-setup.git`.
Если локальный Git ещё не инициализирован:

```sh
git init -b main
git remote add origin git@github.com:romamonk/vps-setup.git
git fetch origin
git branch -r
```

Перед первым коммитом и push проверить существующую удалённую историю;
если репозиторий уже содержит коммиты, сначала согласовать с ней локальные файлы.
