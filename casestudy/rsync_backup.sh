#!/bin/bash
set -aueo pipefail
declare -r RSYNC_USER="rsync_backup"
declare -r RSYNC_HOST="10.0.0.194"
declare -r RSYNC_MODULE="data"
declare -r RSYNC_PASS_FILE="/etc/rsync.client"
declare HOST_IP
HOST_IP=$(hostname -I | awk '{print $1}')
declare -r BACKUP_DIR="/backup"

rsync_backup() {
  rsync -avz "${BACKUP_DIR}/"  --delete --password-file="${RSYNC_PASS_FILE}" ${RSYNC_USER}@${RSYNC_HOST}::${RSYNC_MODULE}
}

crete_md5() {
  md5sum "${BACKUP_DIR}/${HOST_IP}/" > "${BACKUP_DIR}/${HOST_IP}/check.md5"
}

back_file() {
   [ ! -d "${BACKUP_DIR}/${HOST_IP}" ]  && mkdir -p "${BACKUP_DIR}/${HOST_IP}"
   # 打包
   tar -zcf "${BACKUP_DIR}/${HOST_IP}/etc_$(date +%Y%m%d_%W).tar.gz" /etc/
}
main() {
  back_file

  rsync_backup

}
main "$@"