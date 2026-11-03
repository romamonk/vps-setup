# Playbooks

Порядок: `bootstrap.yml`, переход на admin, `configure.yml`, `harden.yml`,
`verify.yml`. Команды и ограничения приведены в корневом README.

`reboot.yml` запускается отдельно, после сохранения работы и проверки доступа.
Он перезагружает сервер только при наличии `/var/run/reboot-required`.
После reboot `configure.yml` может заново создать пустую tmux-сессию.
