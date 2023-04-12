# How to use Percona Xtrabackup for Backing Up MySQL Databases?

This document (or README) will have a guide to how, a/any mysql (v8+) database can be backed up using **[percona `xtrabackup`](https://docs.percona.com/percona-xtrabackup/8.0/)**.

This document (or README) also takes help from the **[do-community](https://github.com/do-community/ubuntu-1604-mysql-backup)** (DigitalOcean-Community), and **[this amazing blog](https://www.digitalocean.com/community/tutorials/how-to-configure-mysql-backups-with-percona-xtrabackup-on-ubuntu-16-04)**.

## Setup Process

In _main server_ (and optionally in _backup server_), install the following tools:

- **[Install MySQL (v8+)](https://www.percona.com/blog/installing-mysql-8-on-ubuntu-16-04-lts/)**.

In both the _main server_ and _backup server_, install the following tools:

- Install **[Percona Xtrabackup](https://docs.percona.com/percona-xtrabackup/8.0/installation.html)**.
- Install `qpress`: **`apt-get update && apt-get install qpress`**

## User Setup Steps (Configuring a MySQL `backup` User) [Optional]

- Startup a MySQL session with MySQL root user:

  ```bash
  bash@linux $ mysql -u root -p
  ```

- Create a new user called `backup` as follows:

  ```sql
  mysql> CREATE USER 'backup'@'localhost' IDENTIFIED BY 'password';
  ```

  Note that `password` is something that the user chooses what they want to use.

- The `backup` user should be able to perform all the actions required for backing up data, and for that, all permissions for backing up data should be provided:

  ```sql
  mysql> GRANT SELECT, INSERT, CREATE, RELOAD, PROCESS, SUPER, LOCK TABLES, REPLICATION CLIENT, CREATE TABLESPACE, BACKUP_ADMIN ON *.* TO `backup`@`localhost`;
  mysql> FLUSH PRIVILEGES;
  mysql> exit;
  ```

- Make sure that group and user data is available for the `backup` user is available

  ```bash
  bash@linux $ grep backup /etc/passwd /etc/group
  ```

- Add the `backup` user to `mysql` group as follows:

  ```bash
  bash@linux $ sudo usermod -aG mysql backup
  ```

- Add the sudo user to the `backup` group as follows:

  ```bash
  bash@linux $ sudo usermod -aG backup ${USER}
  ```

  NOTE: `${USER}` is used to indicate the user that's a sudoer.

- Verify whether the `backup` user has been added to the `mysql` group and the user has been added to the `backup` group:

  ```bash
  bash@linux $ grep backup /etc/group
  backup:x:34:user    # `user` is a part of `backup` group
  mysql:x:116:backup  # `backup` is a part of `mysql` group
  ```

- [**optional-step**] We can restrict the permissions for `/var/lib/mysql` (which is the default mysql data directory) as follows:

  ```bash
  bash@linux $ sudo find /var/lib/mysql -type d -exec chmod 750 {} \;
  ```

  NOTE: In MySQL terminal, we can get the current data directory as follows (by default, it should be `/var/lib/mysql`)

  ```sql
  mysql> SELECT @@datadir;
  ```

  And we should see something like the following:

  ```terminal
  +-----------------+
  | @@datadir       |
  +-----------------+
  | /var/lib/mysql/ |
  +-----------------+
  1 row in set (0.00 sec)
  ```

- Create a MySQL Configuration File with the Backup Parameters:

  ```bash
  bash@linux $ sudo nano /etc/mysql/backup.cnf
  ```

  And `backup.cnf` would have the following content:

  ```cnf
  [client]
  user=backup
  password=password
  ```

  NOTE: `password` is the password we set when we added the `backup` user in MySQL.

  - Give ownership of the file to the `backup` user and then restrict the permissions so that no other users can access the file:

    ```bash
    bash@linux $ sudo chown backup /etc/mysql/backup.cnf
    bash@linux $ sudo chmod 600 /etc/mysql/backup.cnf
    ```

## Proposed Backup Directory Structure

```bash
# LSN: Log Sequence Number

/backups/
|—— db/
|    |—— mysql/
|    |   |—— scripts/  # This is the place where all the backup scripts related to mysql will exist
|    |   |—— dumps/    # Should contain all the dumps for the cycle selected. NOTE: The naming of each directory will be Date Based.
|    |   |   |—— cycle_1_dumps/  # These can be dumps related to starting 2 weeks of the month in which, full backup is taken once, and remaining are all incremental backups
|    |   |   |   |—— full_backup/
|    |   |   |   |   |—— dump.xbstream
|    |   |   |   |   |—— xtrabackup_checkpoints # Contains the information of LSN for innodb backups. Information here is important for taking Incremental Backups
|    |   |   |   |   |—— xtrabackup_info
|    |   |   |   |—— incremental_backup_1/
|    |   |   |   |   |—— dump.xbstream
|    |   |   |   |   |—— xtrabackup_checkpoints
|    |   |   |   |   |—— xtrabackup_info
|    |   |   |   |—— incremental_backup_2/
|    |   |   |   |   |—— dump.xbstream
|    |   |   |   |   |—— xtrabackup_checkpoints
|    |   |   |   |   |—— xtrabackup_info
|    |   |   |   |—— ...
|    |   |   |—— cycle_2_dumps/  # These can be dumps related to last 2 weeks of the month in which, full backup is taken once, and remaining backups are all incremental
|    |   |   |—— ... # More dumps - Ex: there might be a maximum of previous 6 months data stored => 26 weeks or cycles' data.
|    |   |—— logs/ # Only stores the recent logs. Logs of individual backups will be stored in their own directories
|    |   |   |—— xtrabackup_checkpoints_all
|    |   |   |—— xtrabackup_log # [Optional]: Can be used to store the most recent `xtrabackup` log
|    |   |   |—— extract_log    # [Optional]: Can be used to store the most recent extract, decrypt & decompress log
|    |   |—— restore/  # [Optional]: Generated when the backup is getting restored using `xtrabackup --prepare` command
|    |   |   |—— cycle_1_dumps/
|    |   |   |   |—— full_backup/
|    |   |   |   |—— incremental_backup_1/
|    |   |   |   |—— incremental_backup_2/
```

**NOTE**: The documentation below this point can change with respect to any new findings in the `xtrabackup` tooling and changes in scripting.

---

## Taking Backups using `xtrabackup` command

Most of the information here is sourced from:

1. **[Percona Xtrabackup Official Documentation](https://docs.percona.com/percona-xtrabackup/8.0/backup_scenarios/full_backup.html)**
   - **[Percona Forum](https://forums.percona.com/t/xtrabackup-8-0-14-mysql-8-0-21-access-denied-for-user-backup-localhost/8691)**
2. **[do-community/ubuntu-1604-mysql-backup](https://github.com/do-community/ubuntu-1604-mysql-backup) GitHub Repo**

**NOTE**: For using `xtrabackup`, we may require elevated superuser privileges &mdash; `sudo`.

- Full Backup

  ```bash
  xtrabackup \
  --defaults-file=/etc/mysql/backup.cnf \
  --backup \
  --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/
  ```

  - The backup will be taken inside `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/` directory, hence ensure that `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/` directory exists.
  - If the config file at `/etc/mysql/backup.cnf` is not created, then instead of `--defaults-file`, we have to give `--user=<db-user>` and `--password=<db-user-password>` options.

- Full Backup w/ Compression (using `qpress`):

  ```bash
  # Avoid '--compress=lz4' option. Reason given below.
  xtrabackup \
  --defaults-file=/etc/mysql/backup.cnf \
  --backup \
  --compress=lz4 \
  --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/
  ```

  NOTES:
  1. If `--compress` is used, by default `qpress` (or quick-lz) algo is used to compress the backup, for which `qpress` is supposed to be installed for sure ([`percona-release enable tools && apt update && apt install qpress`](https://docs.percona.com/percona-xtrabackup/8.0/backup_scenarios/compressed_backup.html#create-compressed-backups))
  2. `lz4` (another compression tool) was working on the face of it, but when decompressing the dump, all of the files had 0B size, which means that data was getting corrupted. **So better avoid `lz4`**.

  ```bash
  xtrabackup \
  --defaults-file=/etc/mysql/backup.cnf \
  --backup \
  --compress \
  --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/
  ```

- Full Backup w/ Compression & Streaming

  ```bash
  xtrabackup \
  --defaults-file=/etc/mysql/backup.cnf \
  --backup \
  --compress \
  --stream=xbstream \
  --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/ > /backups/db/mysql/dumps/cycle_1_dumps/full_backup/dump.xbstream
  ```

  This will generate a `backup.xbstream` stream file which can be used to continuosly stream the the backup to another command/script as a streaming input.

- Full Backup w/ Compression, Streaming & Encryption

  ```bash
  # Generate a random encryption key and store it at '/backups/db/mysql/dumps/cycle_1_dumps/keyfile'
  echo -n $(openssl rand -base64 24) > /backups/db/mysql/dumps/cycle_1_dumps/keyfile
  
  # Use the generated encryption key to encrypt the data using '--encrypt' and '--encrypt-key-file' options
  xtrabackup \
  --defaults-file=/etc/mysql/backup.cnf \
  --backup \
  --compress \
  --stream=xbstream \
  --encrypt=AES256 \
  --encrypt-key-file=/backups/db/mysql/dumps/cycle_1_dumps/keyfile \
  --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/ > /backups/db/mysql/dumps/cycle_1_dumps/full_backup/dump.xbstream
  ```

- Incremental Backups w/ Compression, Streaming & Encryption

  Take a full backup as shown in the commands above. Now if we assume that at least one full backup exists at `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/`, then take an incremental backup using `last_lsn` number generated in `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/xtrabackup_checkpoints` file.

  **NOTE**: If we're storing the backups as a stream (a `.xbstream` file), then we won't be able to find the `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/xtrabackup_checkpoints` file at all. Instead, we can follow either of the following 2 options we've:

  1. At `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/`, extract \[decrypt] \[decompress] the dump and get the `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/xtrabackup_checkpoints` file to make an incremental backup.
  2. Give an additional parameter `--extra-lsndir=<directory-path>` to `xtrabackup` tool, to get the `xtrabackup_checkpoints` file written into another directory, or the same target directory (which is `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/` directory in this case), and then we can get the information regarding LSN at `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/xtrabackup_checkpoints`.

  Going with option 2 is preferable here because it's counter-intuitive to go through an incremental backup by extracting \[decrypting] \[decompressing] the previous backup to get the `last_lsn` from the file `xtrabackup_checkpoints` file.

  We can also store a global `xtrabackup_checkpoints_all` file which can be a tsv/csv inside the `/backups/mysql/logs/` directory as seen above in the [Proposed Backup Directory Structure](#proposed-backup-directory-structure).

  Therefore, using option 2, we'll have the `--extra-lsndir` option added to all our backups as follows &mdash;

  - Full Backup

    ```bash
    # Use the '--extra-lsndir' option to store the backup checkpoints which contain LSN information to take incremental backups
    xtrabackup \
    --defaults-file=/etc/mysql/backup.cnf \
    --backup \
    --compress \
    --stream=xbstream \
    --encrypt=AES256 \
    --encrypt-key-file=/backups/db/mysql/dumps/cycle_1_dumps/keyfile \
    --extra-lsndir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/
    --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/ > /backups/db/mysql/dumps/cycle_1_dumps/full_backup/dump.xbstream
    ```
  
  - Incremenatal Backup (1)

    ```bash
    # Change should be made in MySQL DB to actually generate a valid incremental backup. 
    # To test this, doing a insert/delete/update in the database will be useful.
    
    # Note the usage of '--incremental-lsn' option
    xtrabackup \
    --defaults-file=/etc/mysql/backup.cnf \
    --backup \
    --compress \
    --stream=xbstream \
    --encrypt=AES256 \
    --incremental-lsn=18234576 \ # This is the 'last_lsn' taken from '/backups/db/mysql/dumps/cycle_1_dumps/full_backup/xtrabackup_checkpoints' file
    --encrypt-key-file=/backups/db/mysql/dumps/cycle_1_dumps/keyfile \
    --extra-lsndir=/backups/db/mysql/dumps/cycle_1_dumps/incremental_backup_1/
    --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/incremental_backup_1/ > /backups/db/mysql/dumps/cycle_1_dumps/incremental_backup_1/dump.xbstream
    ```

  - Incremenatal Backup (2)

    ```bash
    xtrabackup \
    --defaults-file=/etc/mysql/backup.cnf \
    --backup \
    --compress \
    --stream=xbstream \
    --encrypt=AES256 \
    --incremental-lsn=18234942 \ # This is the 'last_lsn' taken from '/backups/db/mysql/dumps/cycle_1_dumps/incremental_backup_1/xtrabackup_checkpoints' file
    --encrypt-key-file=/backups/db/mysql/dumps/cycle_1_dumps/keyfile \
    --extra-lsndir=/backups/db/mysql/dumps/cycle_1_dumps/incremental_backup_2/
    --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/incremental_backup_2/ > /backups/db/mysql/dumps/cycle_1_dumps/incremental_backup_2/dump.xbstream
    ```

  There can be subsequent incremental backups that can be taken as needed.

## Taking Backups & Sending them over Network

- Full Backup

  ```bash
  xtrabackup \
  --defaults-file=/etc/mysql/backup.cnf \
  --backup \
  --compress \
  --stream=xbstream \
  --encrypt=AES256 \
  --encrypt-key-file=/backups/db/mysql/dumps/cycle_1_dumps/keyfile \
  --extra-lsndir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/
  --target-dir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/ | ssh backup "cat - > "/backups/db/mysql/dumps/cycle_1_dumps/full_backup/dump.xbstream""
  ```

NOTE:

1. Instead of `>`, we're streaming/piping the output (using `|`) of the `xtrabackup` command to `cat` via `ssh`ing into destination host (In this case, it is _backup_. Information regarding destination host can be found in `/etc/hosts/` file).
2. Incremental backups can also be streamed via `ssh` as shown above for full backup.
3. The files inside local target directory `/backups/db/mysql/dumps/cycle_1_dumps/full_backup/` will have files like `xtrabackup_checkpoints` and `xtrabackup_info` files which should be moved to the destination host machine in the appropriate directory using `scp` or `rsync`.

We can also log the output of `xtrabackup` command to `/backups/db/mysql/logs/xtrabackup_log` file as follows:

```bash
xtrabackup \
--defaults-file=/etc/mysql/backup.cnf \
--backup \
--compress \
--stream=xbstream \
--encrypt=AES256 \
--encrypt-key-file=/backups/db/mysql/dumps/cycle_1_dumps/keyfile \
--extra-lsndir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/
--target-dir=/backups/db/mysql/dumps/cycle_1_dumps/full_backup/ 2> /backups/db/mysql/logs/xtrabackup_log | ssh backup "cat - > "/backups/db/mysql/dumps/cycle_1_dumps/full_backup/dump.xbstream""
```

Incremental Backups:

```bash
sudo xtrabackup --defaults-file=/etc/mysql/root.cnf --backup --compress --encrypt=AES256 --encrypt-key-file=/home/vagrant/experiment/keyfile --stream=xbstream --target-dir=/home/vagrant/backup/mysql/inc1 --incremental-lsn=18234576 --extra-lsndir=/home/vagrant/backup/mysql/lsndir > dump.xbstream
```

## Preparing Backup & Restoring

**_NOTE: Documentation is yet to be completed for this section._**

```bash
xtrabackup --decrypt=AES256 --encrypt-key-file=/home/vagrant/backups/mysql/keyfile --decompress --remove-original --target-dir=.
```
