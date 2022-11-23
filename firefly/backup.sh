#!/bin/bash

files_to_backup=(.env .db.env .fidi.env docker-compose.yml )

info()  { echo -e "\\033[1;36m[INFO]\\033[0m  \\033[36m$*\\033[0m" >&2; }
warn()  { echo -e "\\033[1;33m[WARNING]\\033[0m  \\033[33m$*\\033[0m" >&2; }
fatal() { echo -e "\\033[1;31m[FATAL]\\033[0m  \\033[31m$*\\033[0m" >&2; exit 1; }

intro () {
    echo " ====================================================="
    echo "     Backup & Restore docker based FireFly III v1.1   "
    echo " ====================================================="
    echo " It automatically detects db & upload volumes based on the name firefly_iii"
    echo " Requirements:"
    echo " - Place the script in the same directory where your docker-compose.yml and .env files are saved"
    echo " Warning: The destination directory is created if it does not exist"
}

usage () {
    echo "Usage: $0 backup|restore /tmp/backup/destination/dir [no_files]"
    echo "- backup|restore - Action you want to execute"
    echo "- destination path of your backup file including file name"
    echo "- optionally backup or restore volumns only when no_files parameter is passed"
    echo "Example backup: $0 backup /home/backup/firefly-2022-01-01.tar"
    echo "Example restore: $0 restore /home/backup/firefly-2022-01-01.tar"
    echo "To backup once per day you can add something like this to your cron:"
    echo "1 01 * * * bash /home/myname/backuper.sh backup /home/backup/\$(date '+%F').tar"
}

backup () {
    script_path="$1"
    if [ ! -d "$(dirname $2)" ]; then
        info "Creating destination directory: $(dirname $2)"
        mkdir -p "$(dirname $2)"
    fi
    full_path=$(realpath $2)
    dest_path="$(dirname $full_path)"
    dest_file="$(basename $full_path)"
    upload_volume="$3"
    no_files=$4

    to_backup=()

    if [ ! -d "$dest_path" ]; then
        warn "Provided destination path does not exist. Creating: $dest_path"
        mkdir "$dest_path"
    fi
    if [ -f "$dest_file" ]; then
        warn "Provided file path already exists: $dest_file. Overwriting"
    fi

    # Create temporary directory
    if [ ! -d "$dest_path/tmp" ]; then
        mkdir "$dest_path/tmp"
    fi

    # Files backup
    if [ $no_files = "false" ]; then
        not_found=()
        for f in "${files_to_backup[@]}"; do
            if [ ! -f "$script_path/$f" ]; then
                not_found+=("$f")
            else
                cp "$script_path/$f" "$dest_path/tmp/"
                to_backup+=("$f")
            fi
        done
        if ((${#not_found[@]})); then
            warn "The following files were not found in $script_path: ${not_found[@]}. Skipping."
        fi
        if ((${#to_backup[@]})); then
            info "Backing up the following files in $script_path: ${to_backup[@]}"
        fi
    fi

    # Version
    app_container=$(docker ps | fgrep firefly_app | cut -d ' ' -f 1)
    app_version=$(docker exec -it $app_container fgrep "'version'" /var/www/html/config/firefly.php | tr -s ' ' | cut -d "'" -f 4)
    db_version=$(docker exec -it $app_container fgrep "'db_version'" /var/www/html/config/firefly.php | tr -s ' ' | tr -d ',' | cut -d " " -f 4)
    info 'Backing up App & database version numbers.'
    echo -e "Application: $app_version\nDatabase: $db_version" > "$dest_path/tmp/version.txt"
    to_backup+=(version.txt)

    # DB container
    db_container=$(docker ps | fgrep firefly_db | cut -d ' ' -f 1)
    if [ -z $db_container ]; then
        warn "db container is not running. Not backing up."
    else
        info 'Backing up database'
        docker exec $db_container bash -c '/usr/bin/mysqldump -u firefly --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE"' > "$dest_path/tmp/firefly_db.sql"
        to_backup+=("firefly_db.sql")
    fi

    # Upload Volume
    if [ -z $upload_volume ]; then
        warn "upload volume does NOT exist. Not backing up."
    else
        info 'Backing up upload volume'
        docker run --rm -v "$upload_volume:/tmp" -v "$dest_path/tmp:/backup" ubuntu tar -czf "/backup/firefly_upload.tar" /tmp
        to_backup+=("firefly_upload.tar")
    fi

    # Compress
    tar -C "$dest_path/tmp" -czf "$dest_path/$dest_file" --files-from <(printf "%s\n" "${to_backup[@]}")

    # Clean up
    for file in "${to_backup[@]}"; do
        rm -f "$dest_path/tmp/$file"
    done
    rmdir "$dest_path/tmp"
}

restore () {
    script_path="$1"
    full_path=$(realpath $2)
    src_path="$(dirname $full_path)"
    backup_file="$(basename $full_path)"
    upload_volume="$3"
    no_files=$4

    if [ ! -f "$src_path/$backup_file" ]; then
        fatal "Provided backup file does not exist: $path"
    fi

    # Create temporary directory
    if [ ! -d "$src_path/tmp" ]; then
        mkdir "$src_path/tmp"
    fi

    # Files backup
    if [ $no_files = "false" ]; then
        tar -C "$src_path/tmp" -xf "$src_path/$backup_file"
        readarray -t <<<$(tar -tf "$src_path/$backup_file")
        # restored=(${MAPFILE[*]})
        not_found=()
        restored=()
        for f in "${files_to_backup[@]}"; do
            if [ ! -f "$script_path/$f" ]; then
                not_found+=("$f")
            else
                cp "$src_path/tmp/$f" .
                restored+=("$f")
            fi
        done
        if ((${#not_found[@]})); then
            warn "The following files were not found in $script_path: ${not_found[@]}. Skipping."
        fi
        if ((${#restored[@]})); then
            info "Restoring the following files: ${restored[@]}"
        fi
    else
        tar -C "$src_path/tmp" -xf "$src_path/$backup_file" firefly_db.sql firefly_upload.tar
        restored=(firefly_db.sql firefly_upload.tar)
    fi

    if [ ! -z $upload_volume ]; then
        warn "The upload volume exists. Overwriting."
    fi

    docker run --rm -v "$upload_volume:/recover" -v "$src_path/tmp:/backup" ubuntu tar -xf /backup/firefly_upload.tar -C /recover --strip 1
    restored+=(firefly_upload.tar)

    db_container=$(docker ps | fgrep firefly_db | cut -d ' ' -f 1)

    if [ -z $db_container ]; then
        warn "The db container is not running. Not backing up."
    else
        info 'Restoring database'
        cat "$src_path/tmp/firefly_db.sql" | docker exec -i $db_container bash -c '/usr/bin/mysql -u firefly --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE"'
        restored+=(firefly_db.sql)
    fi

    restored+=(version.txt)
    # Clean up
    for file in "${restored[@]}"; do
        rm -f "$src_path/tmp/$file"
    done
    rmdir "$src_path/tmp"
}

main () {
    intro

    if [ $# -lt 2 ]; then
        fatal "Not enough parameters.\n$(usage)"
    fi
    current_dir="$(dirname $0)"
    action=$1
    path="$2"
    if [ -z "$3" ]; then
        no_files=false
    else
        no_files=true
    fi

    if [ -d "$path" ]; then
        fatal "Path is the existing directory. It has to a file path"
    fi

    upload_volume="$(docker volume ls | fgrep firefly_iii_upload | tr -s ' ' | cut -d ' ' -f 2)"

    if [ "$action" == 'backup' ]; then
        backup "$current_dir" "$path" "$upload_volume" $no_files
    elif [ "$action" == 'restore' ]; then
        restore "$current_dir" "$path" "$upload_volume" $no_files
    else
        fatal "Unrecognized action $action\n$(usage)"
    fi
}

main "$@"