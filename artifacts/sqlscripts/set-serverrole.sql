-- Add the credential to the SQL Server administrators domain login 
ALTER LOGIN [test\testo-sql]
ADD CREDENTIAL sysadmin_ekm_cred;
GO