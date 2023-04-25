
CREATE USER IF NOT EXISTS 'backup'@'localhost' IDENTIFIED BY 'password';

GRANT 
  SELECT, 
  RELOAD, 
  PROCESS, 
  SUPER, 
  LOCK TABLES, 
  REPLICATION CLIENT, 
  BACKUP_ADMIN 
ON 
  *.* 
TO 
  `backup`@`localhost`;

FLUSH PRIVILEGES;
