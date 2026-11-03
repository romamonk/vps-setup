# Справочник inventory

Запускайте команды из корня репозитория с `-i inventories/local/hosts.yml`.
Ansible подхватывает соседний `group_vars/all.yml`. Реальные адреса, ключи
и параметры храните только в локальном inventory, исключённом из Git.
Пароли и содержимое приватных ключей не записывайте даже туда.

## Подключение к VPS

| Параметр | Значение в примере | Назначение |
| --- | --- | --- |
| `ansible_host` | `vps.example.invalid` | Адрес конкретного VPS; заменить перед запуском |
| `ansible_user` | `REPLACE_WITH_INITIAL_SSH_USER` | Исходный root/sudo-пользователь; после bootstrap заменить на `admin_user` |
| `ansible_port` | `22` | Существующий порт SSH; должен совпадать с `ssh_port` |
| `ansible_ssh_private_key_file` | Не задан | Необязательный локальный путь к ключу подключения Ansible |
| `ansible_python_interpreter` | Не задан | Автоопределение Python; можно явно задать `/usr/bin/python3` |

Последние два параметра можно добавить к хосту в локальном `hosts.yml`.
Путь к ключу подключения Ansible и пути ключей проверок ниже — разные настройки;
при нестандартных ключах согласуйте их. Приватные ключи не копируются на VPS.

Шаблон рассчитан на прямое подключение. Проверки вызывают локальный `ssh`
с адресом, портом и `-i`; `ansible_ssh_common_args`, ProxyJump и нестандартный
known_hosts из параметров Ansible в эти вызовы не переносятся. Системный/локальный
SSH config применяется самим OpenSSH. Сценарий через bastion не проверен.

## Пользователи и ключи

| Параметр | По умолчанию | Поведение |
| --- | --- | --- |
| `admin_user` | `admin` | Пользователь с sudo; не root и не совпадает с agent |
| `agent_user` | `agent` | Непривилегированный пользователь |
| `admin_authorized_keys` | `[]` | Непустой список строк публичных ключей admin |
| `agent_authorized_keys` | `[]` | Непустой список строк публичных ключей agent |
| `admin_private_key_file` | `$HOME/.ssh/id_ed25519` на контроллере | Ключ для независимого теста SSH admin |
| `agent_private_key_file` | Значение `admin_private_key_file` | Ключ для теста SSH agent |
| `admin_passwordless_sudo` | `true` | Правило NOPASSWD для admin; `false` требует заранее установленного пароля |
| `agent_workspace_dir` | `/home/<agent_user>/workspace` | Рабочий каталог, владелец agent, права `0700` |

Публичные ключи можно загрузить локальным lookup, например:

```yaml
admin_authorized_keys:
  - "{{ lookup('file', lookup('env', 'HOME') + '/.ssh/id_ed25519.pub') }}"
agent_authorized_keys: '{{ admin_authorized_keys }}'
```

Имена допускают строчные латинские буквы, цифры, `_` и `-`, начинаются с буквы
или `_`. Используются домашние каталоги `/home/<имя>`. Существующие пользователи
с другим home или primary group требуют отдельной адаптации; переименование
пользователей и перенос их данных не реализованы.

Bootstrap устанавливает bash и права `0700` на home обоих пользователей,
**удаляет все дополнительные группы agent**, добавляет admin в sudo.
Существующие публичные ключи сохраняются: удаление строки из inventory само
по себе не отзывает доступ. Проверка через `sudo -l` выявляет оставшиеся
sudo-разрешения agent, но bootstrap не удаляет произвольные старые sudoers-правила.

## SSH и firewall

| Параметр | По умолчанию | Поведение |
| --- | --- | --- |
| `ssh_port` | `22` | Текущий порт для проверок/UFW/fail2ban; не меняет порт sshd |
| `ssh_allowed_cidrs` | `[]` | Непустой список CIDR; должен включать адрес текущего SSH-клиента |
| `public_tcp_ports` | `[]` | Дополнительные TCP-порты, открываемые для любых источников |
| `recovery_access_confirmed` | `false` | Ручное подтверждение доступа к консоли провайдера; harden/reboot требуют `true` |
| `ssh_tcp_forwarding` | `'yes'` | Допустимы строки `'yes'`, `'local'`, `'no'`; настройка TCP-туннелей |

Для намеренно публичного SSH: `ssh_allowed_cidrs: ['0.0.0.0/0', '::/0']`.
X11 и SSH-agent forwarding запрещаются независимо от TCP forwarding.
Проверки требуют доверенного host key в локальном known_hosts.

UFW выставляет default deny incoming/allow outgoing и добавляет разрешения.
Старые разрешения автоматически не удаляются; `public_tcp_ports: []` не закрывает
ранее открытые порты. Провайдерский firewall шаблон не настраивает. Управление
UDP-портами, миграция SSH-порта и полная сверка существующих UFW-правил отсутствуют.

## Инструменты

| Параметр | По умолчанию | Поведение |
| --- | --- | --- |
| `install_fail2ban` | `true` | Установка, включение sshd jail с systemd backend |
| `install_claude_code` | `true` | Native Claude под agent, начальная установка stable |
| `install_go` | `false` | Пакет Ubuntu `golang-go` |
| `install_python_tools` | `false` | Пакеты `python3-venv`, `python3-pip`; Python 3 нужен независимо от флага |
| `install_nodejs` | `false` | Пакеты Ubuntu `nodejs`, `npm` |
| `install_docker` | `false` | `true` останавливает configure: реализация Docker отсутствует |
| `claude_installer_sha256` | Проверенная сумма в примере inventory | SHA256 скрипта `https://claude.ai/install.sh`, не версии Claude |

Флаги управляют установкой, **не удалением**. Переключение в `false` не удаляет
пакеты, Claude или уже включённый fail2ban. Выключение соответствующего флага
также пропускает его опциональную проверку в verify.

Базовые git, tmux, curl, CA certificates, jq, ripgrep, unzip, build-essential,
ACL, UFW и unattended-upgrades устанавливаются независимо от флагов toolchains.
Версии пакетов выбираются репозиториями Ubuntu, а не фиксируются в inventory.
Коллекции Ansible заданы диапазонами версий, Python-зависимости — точными
версиями; побитовая воспроизводимость окружения не гарантируется.

Проверка SHA256 установщика выполняется при каждом configure, даже если Claude
уже установлен. При изменении скрипта остановка ожидаема: изучите новую версию
по официальному источнику и только затем обновляйте контрольную сумму.
`creates` предотвращает повторную установку существующего launcher;
изменение SHA256 само по себе не переустанавливает и не понижает версию Claude.
