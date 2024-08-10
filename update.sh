#!/bin/bash

# URL файла с черным списком
blacklist_url="https://github.com/C24Be/AS_Network_List/raw/main/blacklists/blacklist.txt"

# Локальный путь для временного хранения скачанного файла
local_blacklist_file="/var/tmp/blacklist.txt"
# Файл для хранения IP-адресов, добавленных нашим скриптом
managed_ips_file="/var/log/rugov_blacklist/rugov_blacklist.txt"
# Файл для хранения текущих правил UFW
current_ufw_rules_file="/var/log/rugov_blacklist/current_ufw_rules.txt"
# Файл для хранения полного вывода ufw status
ufw_status_file="/var/log/rugov_blacklist/ufw_status_output.txt"

# Создание необходимых файлов и директорий, если они не существуют
echo "Создание необходимых директорий и файлов..."
mkdir -p /var/log/rugov_blacklist
touch "$managed_ips_file"
touch "$local_blacklist_file"
touch "$current_ufw_rules_file"
touch "$ufw_status_file"
echo "Готово."

# Проверка существования файлов
if [[ ! -f "$managed_ips_file" ]]; then
    echo "Ошибка: Файл $managed_ips_file не создан."
    exit 1
fi
if [[ ! -f "$local_blacklist_file" ]]; then
    echo "Ошибка: Файл $local_blacklist_file не создан."
    exit 1
fi
if [[ ! -f "$current_ufw_rules_file" ]]; then
    echo "Ошибка: Файл $current_ufw_rules_file не создан."
    exit 1
fi
if [[ ! -f "$ufw_status_file" ]]; then
    echo "Ошибка: Файл $ufw_status_file не создан."
    exit 1
fi

# Скачивание списка
download_blacklist() {
    echo "Скачивание черного списка..."
    if wget -O "$local_blacklist_file" "$blacklist_url"; then
        echo "Черный список скачан в $local_blacklist_file."
    else
        echo "Ошибка: Не удалось скачать черный список."
        exit 1
    fi
}

# Получение текущего списка заблокированных IP из ufw
get_current_ufw_rules() {
    echo "Получение текущих правил UFW..."
    sudo ufw status > "$ufw_status_file"
    if [[ $? -ne 0 ]]; then
        echo "Ошибка: Не удалось выполнить 'ufw status'."
        exit 1
    fi

    # Извлечение IP-адресов с маской из вывода ufw status
    awk '/DENY/{print $3}' "$ufw_status_file" > "$current_ufw_rules_file"
    if [[ $? -eq 0 ]]; then
        echo "Текущие правила UFW сохранены в $current_ufw_rules_file."
    else
        echo "Ошибка: Не удалось получить текущие правила UFW."
        exit 1
    fi
}

# Обновление правил UFW
update_ufw() {
    echo "Обновление правил UFW..."
    new_ips=()
    while IFS= read -r line; do
        ip=$(echo "$line" | tr -d '[:space:]')
        if [[ ! -z "$ip" && ! "$ip" =~ ^# ]]; then
            new_ips+=("$ip")
            if ! grep -q "$ip" "$managed_ips_file"; then
                add_ip_to_ufw "$ip"
            fi
        fi
    done < "$local_blacklist_file"

    for existing_ip in $(cat "$managed_ips_file"); do
        if [[ ! " ${new_ips[@]} " =~ " ${existing_ip} " ]]; then
            remove_ip_from_ufw "$existing_ip"
        fi
    done
    echo "Правила UFW обновлены."
}

# Добавление IP в UFW
add_ip_to_ufw() {
    echo "Блокировка IP: $1"
    if sudo ufw deny from "$1"; then
        echo "$1" >> "$managed_ips_file"
        echo "Заблокирован IP: $1"
    else
        echo "Ошибка: Не удалось заблокировать IP $1"
    fi
}

# Удаление IP из UFW
remove_ip_from_ufw() {
    echo "Разблокировка IP: $1"
    if sudo ufw delete deny from "$1"; then
        sed -i "\|$1|d" "$managed_ips_file"
        echo "Разблокирован IP: $1"
    else
        echo "Ошибка: Не удалось разблокировать IP $1"
    fi
}

download_blacklist
get_current_ufw_rules
update_ufw

echo "Скрипт выполнен успешно."
