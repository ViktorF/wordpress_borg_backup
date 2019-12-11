#!/bin/sh

# Features we want

## Accept the following
    ### backup_dir (MANDATORY)
    ### wordpress_location
    ### wordpress_log_location
    ### wordpress_db_location
    ### site_name 
    ### wp_db_name
    ### wp_db_usename
    ### wp_db_userpwd

    ### borg pass-phrase (MANDATORY)
    ### borg max-backup-size (MANDATORY)

    ### log_rotate size
    ### total log_size
    ### log_off

## Assume the following
    ### backup_dir -> ~/backups/site_name
    ### wordpress_location -> find it from nginx config
        ### For more than 1 nginx sites -> prompt which one to use
        ### backup all???
    ### wordpress_log_location -> find it from nginx config
    ### site_name -> find it from nginx config
    ### wp_db_name -> get it from wordpress_location -> wp_config
    ### wp_db_usename -> get it from wordpress_location -> wp_config
    ### wp_db_userpwd -> get it from wordpress_location -> wp_config
        # https://stackoverflow.com/questions/32400933/how-can-i-list-all-vhosts-in-nginx
        # sudo nginx -T | perl -ln0777e '$,=$\; s/^\s*#.*\n//mg; print grep !$u{$_}++ && !m/^_$/, map m/(\S+)/g, m/\bserver_name\s++(.*?)\s*;/sg'
        # sudo nginx -T | grep "server_name " | sed 's/.*server_name \(.*\);/\1/'
            # -> Check if it starts with # (i.e. - deactivated)
            # -> Check if it has a corresponding (uncommented out) "root" in the same {} or any of the included files in that {}

## Fail on following
    ### No sudo 
    ### No nginx and no wordpress_location, wp_db_name, wp_db_username, wp_db_userpwd
    ### If same script is currently running for the same site - fail

## Create a DB backup and put it at tmp/wp_backup_script/site_name/db_bkp
    ### Delete if already exists
    ### mysqldump --user=username --password=password --opt DatabaseName > database.sql
    ### delete it after successful backup creation
    ### Run low-priority

## Do a borg init - if it is not NOT done on the backup_dir
    ### On init - show the key file on screen at the END (NOT on log)
## Do a borg create with the timestamp
    ### Run low-priority

## Log all output to backup_dir/logs folder
    ### Log rotate and delete if required
    ### If log_off been mentioned - send logs to /dev/null

## On ERROR -> output to backup_dir/logs/error
    ### Add it to system log as well - even if log_off



# For the README.md
    ## Ensure you have sudo
    ## If you have nginx and not providing the wordpress_location, wp_db_name, wp_db_username, wp_db_userpwd details - $ sudo nginx -t gives all OK
    ## Ensure you have enough space at the backup location
    ## If choosen to switch off log - check system error messages for "wp_backup_script_errors"
    ## DB backup is created and stored in tmp/wp_backup_script/site_name/db_bkp 
        ### This is deleted after successful backup
    ## If you want to schedule it - put it in appropriate location
        ### Explain where - give links for more details
    ## Runs on low priority - so system resources are NOT overloaded


backup_name=wp-baseline
backup_dir=/home/pratik/backup/borg/
log_dir=/home/pratik/logs/borg/
unique_identifier=pratik

#########################################################################

readonly backup_name
readonly backup_dir
readonly log_dir
readonly unique_identifier

# Setting this, so you won't be asked for your repository passphrase:
export BORG_PASSPHRASE='d00x^UXryuEYTwPuZwQh'

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=$backup_dir$backup_name

# some helpers and error handling:
log_file=$log_dir$backup_name-$(date +%d%m%Y-%H%M%S)
readonly log_file

# if borg is currently running - stop sync
if [ $(pidof borg | wc -w) -eq 1 ]
then
  echo "Another Backup is currently running. Exiting." >> $log_file 2>&1
  exit 2
fi

info() { printf "\n%s %s\n\n" "$( date )" "$*" >> $log_file 2>&1; }
trap 'echo $( date ) Backup interrupted >> $log_file 2>&1; exit 2' INT TERM

info "Starting backup" >> $log_file 2>&1

# Backup the most important directories into an archive named after
# the machine this script is currently running on:
borg create                                             \
    --verbose                                           \
    --filter AME                                        \
    --list                                              \
    --stats                                             \
    --show-rc                                           \
    --compression zstd,3                                \
    --exclude-caches                                    \
    --exclude '/home/*/.cache/*'                        \
    --exclude '/home/*/.local/share/Trash/*'            \
    --exclude '/var/cache/*'                            \
    --exclude '/var/tmp/*'                              \
    --exclude "$backup_dir"                             \
    --exclude "$log_file"                               \
    ::"$unique_identifier-$backup_name-{now}"           \
    /etc                                                \
    /root                                               \
    /var                                                \
    /srv                                                \
    /opt                                                \
    /usr/local                                          \
    /usr/share/nginx                                    \
    /home                                               \
    >> $log_file 2>&1                                   \

backup_exit=$?

info "Pruning repository" >> $log_file 2>&1

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

borg prune                                       \
    --list                                       \
    --stats                                      \
    --prefix "$unique_identifier-$backup_name"   \
    --show-rc                                    \
    --keep-within 2d                             \
    --keep-last 5                                \
    --keep-daily 7                               \
    >> $log_file 2>&1                            \

prune_exit=$?

# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))

if [ ${global_exit} -eq 1 ];
then
    info "Backup and/or Prune finished with a warning" >> $log_file 2>&1
fi

if [ ${global_exit} -gt 1 ];
then
    info "Backup and/or Prune finished with an error" >> $log_file 2>&1
fi

echo Status Code - $global_exit >> $log_file 2>&1

exit ${global_exit}