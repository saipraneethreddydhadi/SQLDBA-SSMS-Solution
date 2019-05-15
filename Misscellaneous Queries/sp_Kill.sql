USE master
GO

IF OBJECT_ID('dbo.sp_Kill') IS NULL
	EXEC('CREATE PROCEDURE dbo.sp_Kill AS SELECT 1 as Dummy;');
GO

ALTER PROCEDURE dbo.sp_Kill @p_SpId SMALLINT = NULL, 
							@p_DbName VARCHAR(155) = NULL, @p_LoginName VARCHAR(255) = NULL, 
							@p_RollbackStatus BIT = NULL, @p_Force BIT = NULL, 
							@p_AddAuthorizedSessionKiller BIT = 0,
							@p_Help BIT = NULL, @p_Verbose BIT = 0
--WITH EXECUTE AS OWNER
AS
BEGIN -- Proc Body
	/*	Created By:		Ajay Dwivedi
		Version:		0.0
		Modifications:	May 14, 2019 - Creating procedure for 1st time
	*/
	SET NOCOUNT ON;

	IF @p_Verbose = 1
		PRINT 'Declaring Variables..';

	DECLARE @_errorMSG VARCHAR(2000);
	DECLARE @_errorNumber INT;
	DECLARE @_isValidParameterSet bit = 0;
	DECLARE @_callerSPID smallint = @@SPID;
	DECLARE @_callerLoginName varchar(125);
	DECLARE @_runningAsLoginName varchar(125);
	DECLARE @_isKillerSameAsKilled BIT = 0;
	DECLARE @_isAuthorizedSessionKiller BIT = 0;
	DECLARE @_sessionDbName varchar(125);
	DECLARE @_isKillerDbOwner BIT = 0;
	DECLARE @_isKillerSysAdmin BIT = 0;
	DECLARE @_SQLString nvarchar(2000);  
	DECLARE @_ParmDefinition nvarchar(500);

	IF OBJECT_ID('DBA..AuthorizedSessionKiller') IS NULL
	BEGIN
		CREATE TABLE DBA.dbo.AuthorizedSessionKiller(ID INT IDENTITY(1,1), IsDbLevelPermission BIT NOT NULL DEFAULT 1, DbName varchar(125) NULL, LoginName varchar(125) NOT NULL, AddedBy varchar(125) NOT NULL, AddedOn datetime NOT NULL DEFAULT GETDATE());
	END

	IF @p_Verbose = 1
		PRINT 'Removing null values from parameters..';
	SELECT @_callerLoginName = s.original_login_name from sys.dm_exec_sessions as s where s.session_id = @_callerSPID;
	SET @_runningAsLoginName = SUSER_NAME();
	SET @p_RollbackStatus = ISNULL(@p_RollbackStatus,0);
	SET @p_Force = ISNULL(@p_Force,0);
	SET @p_Help = ISNULL(@p_Help,0);
	SET @p_Verbose = ISNULL(@p_Verbose,0);
	SET @p_AddAuthorizedSessionKiller = ISNULL(@p_AddAuthorizedSessionKiller,0);

	IF @p_Verbose = 1
	BEGIN
		PRINT 'Values of Parameters:- ';
		PRINT CHAR(9)+'@p_SpId = '+CAST(ISNULL(@p_SpId,'NULL') AS VARCHAR(5));
		PRINT CHAR(9)+'@p_DbName = '+CAST(ISNULL(@p_DbName,'NULL') AS VARCHAR(255));
		PRINT CHAR(9)+'@p_LoginName = '+CAST(ISNULL(@p_LoginName,'NULL') AS VARCHAR(255));
		PRINT CHAR(9)+'@p_RollbackStatus = '+CAST(@p_RollbackStatus AS VARCHAR(5));
		PRINT CHAR(9)+'@p_Force = '+CAST(@p_Force AS VARCHAR(5));
		PRINT CHAR(9)+'@p_AddAuthorizedSessionKiller = '+CAST(@p_AddAuthorizedSessionKiller AS VARCHAR(5));		
		PRINT CHAR(9)+'@p_Help = '+CAST(@p_Help AS VARCHAR(5));
		PRINT CHAR(9)+'@p_Verbose = '+CAST(@p_Verbose AS VARCHAR(5));
			
		PRINT CHAR(9)+'@_callerSPID = '+CAST(@_callerSPID AS VARCHAR(5));
		PRINT CHAR(9)+'@_callerLoginName = '+ISNULL(@_callerLoginName, 'NULL');
		PRINT CHAR(9)+'@_runningAsLoginName = '+ISNULL(@_runningAsLoginName,'NULL');
		PRINT CHAR(9)+'@_isAuthorizedSessionKiller = '+CAST(@_isAuthorizedSessionKiller AS VARCHAR(5));		
	END

	IF @p_Verbose = 1
		PRINT 'Start - verification of provided parameter values..';

	-- Validate that At least one valid parameter value if provided
	IF @p_SpId IS NULL AND (@p_Help IS NULL OR @p_Help = 0) AND @p_DbName IS NULL AND @p_LoginName IS NULL AND (@p_AddAuthorizedSessionKiller IS NULL OR @p_AddAuthorizedSessionKiller <> 1)
	BEGIN
		SET @_errorMSG = 'Kindly provide value for at least one of the following parameters:-'+char(10)+char(13)+'@p_SpId, @p_Help, @p_DbName, @p_LoginName, or @p_AddAuthorizedSessionKiller';
		IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
			EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
		ELSE
			EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
	END

	-- Validate if valid parameter set is provided with @p_SpId
	IF @p_SpId IS NOT NULL
	BEGIN
		SET @_isValidParameterSet = 1;
		SELECT @_isValidParameterSet = CASE WHEN @p_DbName IS NOT NULL OR @p_LoginName IS NOT NULL OR 
												 (@p_Force IS NOT NULL AND @p_Force = 1) OR 
												 (@p_AddAuthorizedSessionKiller IS NOT NULL AND @p_AddAuthorizedSessionKiller = 1) OR
												 (@p_Help IS NOT NULL AND @p_Help = 1)		
											THEN 0
											ELSE 1
											END;
		IF @_isValidParameterSet = 0
		BEGIN
			SET @_errorMSG = 'Parameters @p_SpId is not compatible with @p_Help, @p_DbName, @p_LoginName & @p_AddAuthorizedSessionKiller. Kindly keep values for these to default(NULL/0).';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END
	END

	-- Validate if valid parameter set is provided with @p_RollbackStatus
	IF @p_RollbackStatus IS NOT NULL AND @p_RollbackStatus = 1
	BEGIN
		SET @_isValidParameterSet = 1;
		SELECT @_isValidParameterSet = CASE WHEN @p_SpId IS NULL OR @p_SpId < 50 THEN 0 ELSE 1 END;

		IF @_isValidParameterSet = 0
		BEGIN
			SET @_errorMSG = 'Provided value for parameter @p_SpId is not valid with @p_RollbackStatus parameter.';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END
	END

	-- Validate if valid parameter set is provided with @p_DbName
	IF @p_DbName IS NOT NULL
	BEGIN
		SET @_isValidParameterSet = 1;
		SELECT @_isValidParameterSet = CASE WHEN @p_SpId IS NOT NULL OR (@p_Help IS NOT NULL AND @p_Help = 1) OR (@p_RollbackStatus IS NOT NULL AND @p_RollbackStatus = 1)	
											THEN 0
											WHEN (@p_AddAuthorizedSessionKiller IS NULL OR @p_AddAuthorizedSessionKiller <> 1) AND (@p_Force IS NULL OR @p_Force <> 1)	
											THEN 0
											ELSE 1
											END;
		IF @_isValidParameterSet = 0
		BEGIN
			SET @_errorMSG = 'Parameter @p_DbName require values for either @p_Force(=1) & @p_AddAuthorizedSessionKiller(=1).';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END
	END

	-- Validate if valid parameter set is provided with @p_LoginName
	IF @p_LoginName IS NOT NULL
	BEGIN
		SET @_isValidParameterSet = 1;
		SELECT @_isValidParameterSet = CASE WHEN @p_SpId IS NOT NULL OR (@p_Help IS NOT NULL AND @p_Help = 1) OR (@p_RollbackStatus IS NOT NULL AND @p_RollbackStatus = 1)	
											THEN 0
											WHEN (@p_AddAuthorizedSessionKiller IS NULL OR @p_AddAuthorizedSessionKiller <> 1) AND (@p_Force IS NULL OR @p_Force <> 1)	
											THEN 0
											ELSE 1
											END;
		IF @_isValidParameterSet = 0
		BEGIN
			SET @_errorMSG = 'Parameter @p_LoginName require values for either @p_Force(=1) & @p_AddAuthorizedSessionKiller(=1).';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END
	END

	-- Validate if valid parameter set is provided with @p_RollbackStatus
	IF @p_RollbackStatus IS NOT NULL AND @p_RollbackStatus = 1
	BEGIN
		SET @_isValidParameterSet = 1;
		SELECT @_isValidParameterSet = CASE WHEN @p_SpId IS NULL OR @p_SpId < 50
											THEN 0
											ELSE 1
											END;
		IF @_isValidParameterSet = 0
		BEGIN
			SET @_errorMSG = 'Parameter @p_RollbackStatus require value for parameter @p_SpId (>= 50).';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END
	END

	-- Validate if valid parameter set is provided with @p_Force
	IF @p_Force IS NOT NULL AND @p_Force = 1
	BEGIN
		SET @_isValidParameterSet = 1;
		SELECT @_isValidParameterSet = CASE WHEN @p_DbName IS NULL AND @p_LoginName IS NULL
											THEN 0
											WHEN @p_AddAuthorizedSessionKiller IS NOT NULL AND @p_AddAuthorizedSessionKiller = 1
											THEN 0
											ELSE 1
											END;
		IF @_isValidParameterSet = 0
		BEGIN
			SET @_errorMSG = 'Parameter @p_Force require values for parameters @p_DbName & @p_LoginName. Also, @p_AddAuthorizedSessionKiller should be either NULL or 0';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END
	END

	-- Validate if valid parameter set is provided with @p_AddAuthorizedSessionKiller
	IF @p_AddAuthorizedSessionKiller IS NOT NULL AND @p_AddAuthorizedSessionKiller = 1
	BEGIN
		SET @_isValidParameterSet = 1;
		SELECT @_isValidParameterSet = CASE WHEN @p_LoginName IS NULL
											THEN 0
											WHEN @p_SpId IS NOT NULL OR (@p_RollbackStatus IS NOT NULL AND @p_RollbackStatus = 1) OR (@p_Force IS NOT NULL AND @p_Force = 1) OR (@p_Help IS NOT NULL AND @p_Help = 1)
											THEN 0
											ELSE 1
											END;
		IF @_isValidParameterSet = 0
		BEGIN
			SET @_errorMSG = 'Parameter @p_AddAuthorizedSessionKiller require value for parameter @p_LoginName (and @p_DbName if available). Also, @p_AddAuthorizedSessionKiller is not compatible with parameters @p_SpId, @p_RollbackStatus, @p_Force & @p_Help.';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END
	END

	-- Validate if valid parameter set is provided with @p_Help
	IF @p_Help IS NOT NULL AND @p_Help = 1
	BEGIN
		SET @_isValidParameterSet = 1;
		SELECT @_isValidParameterSet = CASE WHEN @p_SpId IS NOT NULL OR @p_DbName IS NOT NULL OR @p_LoginName IS NOT NULL OR (@p_RollbackStatus IS NOT NULL AND @p_RollbackStatus = 1) OR (@p_Force IS NOT NULL AND @p_Force = 1) OR (@p_AddAuthorizedSessionKiller IS NOT NULL AND @p_AddAuthorizedSessionKiller = 1)
											THEN 0
											ELSE 1
											END;
		IF @_isValidParameterSet = 0
		BEGIN
			SET @_errorMSG = 'Parameter @p_Help is not compatible with parameters @p_SpId, @p_DbName, @p_LoginName, @p_RollbackStatus, @p_Force & @p_AddAuthorizedSessionKiller.';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END
	END
	
	IF @p_Verbose = 1
		PRINT 'End - verification of provided parameter values..';

	/* ********************************************************************************************************* */

	IF (@p_SpId IS NOT NULL OR @p_LoginName IS NOT NULL OR @p_DbName IS NOT NULL)
	BEGIN -- Validate Killer Credentials
		IF @p_Verbose = 1
			PRINT 'Begin - Validate Killer Credentials ...';

		IF @p_SpId IS NOT NULL
		BEGIN
			IF @p_Verbose = 1
				PRINT CHAR(9)+'Finding @p_SpId context database..';

			-- Trying to find dbName from running request
			SELECT @_sessionDbName = DB_NAME(r.database_id) 
			FROM sys.dm_exec_sessions as s inner join sys.dm_exec_requests as r 
			ON r.session_id = s.session_id WHERE s.session_id = @p_SpId;

			-- Tyring to find dbName from open transactions
			IF @_sessionDbName IS NULL
			BEGIN
				SELECT	@_sessionDbName = db_name(dt.database_id)
						--,st.session_id, dt.transaction_id
				FROM	sys.dm_tran_session_transactions as st
				INNER JOIN sys.dm_tran_database_transactions as dt
					ON	dt.transaction_id = st.transaction_id
				WHERE	st.session_id = @p_SpId;
			END

			IF @p_Verbose = 1
				PRINT CHAR(9)+CHAR(9)+'@_sessionDbName = '+ISNULL(@_sessionDbName,'NULL');
		END
		
		IF @p_Verbose = 1
			PRINT CHAR(9)+'Check 01 - Is killer part of AuthorizedSessionKiller exception entry';
		IF EXISTS (SELECT * FROM DBA.dbo.AuthorizedSessionKiller as k WHERE k.LoginName = @_callerLoginName AND (k.DbName IS NULL OR k.DbName = COALESCE(@p_DbName,@_sessionDbName)) )
			SET @_isAuthorizedSessionKiller = 1;
		IF @p_Verbose = 1
				PRINT CHAR(9)+CHAR(9)+'@_isAuthorizedSessionKiller = '+CAST(@_isAuthorizedSessionKiller AS VARCHAR(5));


		-- If 1st Check did not pass
		IF @_isAuthorizedSessionKiller <> 1
		BEGIN
			IF @p_SpId IS NOT NULL OR @p_LoginName IS NOT NULL
			BEGIN
				IF @p_Verbose = 1
					PRINT CHAR(9)+'Check 02 - Verify if Killer is same as session owner';
				SELECT @_isKillerSameAsKilled = 1 FROM sys.dm_exec_sessions as s WHERE s.session_id = @p_SpId AND s.login_name = @_callerLoginName;

				IF @_isKillerSameAsKilled <> 1 AND (@p_LoginName IS NOT NULL AND @p_LoginName = @_callerLoginName)
					SET @_isKillerSameAsKilled = 1;		

				IF @p_Verbose = 1
					PRINT CHAR(9)+CHAR(9)+'@_isKillerSameAsKilled = '+CAST(@_isKillerSameAsKilled AS VARCHAR(5));
			END
		END

		-- If 1st & 2nd Check did not pass
		IF @_isKillerSameAsKilled <> 1 AND @_isAuthorizedSessionKiller <> 1
		BEGIN
			IF @p_DbName IS NOT NULL OR (@p_SpId IS NOT NULL AND @_sessionDbName IS NOT NULL)
			BEGIN
				IF @p_Verbose = 1
					PRINT CHAR(9)+'Check 03 - Verify if Killer is [db_owner]';

				SET @_SQLString = N'USE ['+COALESCE(@p_DbName,@_sessionDbName)+']; SELECT @p_isKillerDbOwner_OUT = ISNULL(is_rolemember(''db_owner'', @p_callerLoginName),0)';  
				SET @_ParmDefinition = N'@p_callerLoginName varchar(125), @p_isKillerDbOwner_OUT bit OUTPUT';  

				IF @p_Verbose = 1
					PRINT CHAR(9)+CHAR(9)+'@_SQLString = '+CHAR(10)+@_SQLString;

				EXECUTE sp_executesql @_SQLString, @_ParmDefinition, @p_callerLoginName = @_callerLoginName, @p_isKillerDbOwner_OUT = @_isKillerDbOwner OUTPUT;  

				IF @p_Verbose = 1
					PRINT CHAR(9)+CHAR(9)+'@_isKillerDbOwner = '+CAST(@_isKillerDbOwner AS VARCHAR(5));
			END
		END

		IF @_isKillerSameAsKilled <> 1 AND @_isAuthorizedSessionKiller <> 1 AND @_isKillerDbOwner <> 1
		BEGIN
			IF @p_Verbose = 1
				PRINT CHAR(9)+'Check 04 - Verify if Killer is [sysadmin]';

			SET @_SQLString = N'USE [master]; SELECT @p_isKillerSysAdmin_OUT = ISNULL(IS_SRVROLEMEMBER(''sysadmin'', @p_callerLoginName),0)';  
			SET @_ParmDefinition = N'@p_callerLoginName varchar(125), @p_isKillerSysAdmin_OUT bit OUTPUT';

			IF @p_Verbose = 1
				PRINT CHAR(9)+CHAR(9)+'@_SQLString = '+CHAR(10)+@_SQLString;

			EXECUTE sp_executesql @_SQLString, @_ParmDefinition, @p_callerLoginName = @_callerLoginName, @p_isKillerSysAdmin_OUT = @_isKillerSysAdmin OUTPUT;  

			IF @p_Verbose = 1
				PRINT CHAR(9)+CHAR(9)+'@_isKillerSysAdmin = '+CAST(ISNULL(@_isKillerSysAdmin,'NULL') AS VARCHAR(2));
		END

		IF @p_Verbose = 1
			PRINT 'End - Validate Killer Credentials ...';
	END -- Validate Killer Credentials

	/* ********************************************************************************************************* */


	IF @p_AddAuthorizedSessionKiller = 1
	BEGIN
		IF @p_Verbose = 1
			PRINT 'Begin - [@p_AddAuthorizedSessionKiller = 1]';

		IF @_isKillerSysAdmin = 1
		BEGIN
			PRINT CHAR(9)+'Adding exception for login '+QUOTENAME(@p_LoginName)+' ..';
			-- Validate the same login name + database is not already present
			IF NOT EXISTS (SELECT * FROM DBA.dbo.AuthorizedSessionKiller as k WHERE k.LoginName = @p_LoginName AND ( CASE WHEN @p_DbName IS NOT NULL AND DbName = @p_DbName THEN 1 WHEN @p_DbName IS NULL THEN 1 ELSE 0 END) = 1)
			BEGIN
				INSERT DBA.dbo.AuthorizedSessionKiller
				(IsDbLevelPermission, DbName, LoginName , AddedBy)
				SELECT	[IsDbLevelPermission] = CASE WHEN @p_DbName IS NOT NULL THEN 1 ELSE 0 END
						,@p_DbName	,@p_LoginName ,@_callerLoginName;
			END

			PRINT 'Login '+QUOTENAME(@p_LoginName)+' is added successfully';
		END
		ELSE
		BEGIN
			SET @_errorMSG = 'Login '+QUOTENAME(@_callerLoginName)+' is not SysAdmin on server. So not authorized to add Exception.';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END

		IF @p_Verbose = 1
			PRINT 'End - [@p_AddAuthorizedSessionKiller = 1]';
	END

	IF @p_Help = 1
	BEGIN
		IF @p_Verbose=1 
			PRINT	'
/*	******************** Begin:	@p_Help = 1 *****************************/';

		-- VALUES constructor method does not work in SQL 2005. So using UNION ALL
		SELECT	[Parameter Name], [Data Type], [Default Value], [Parameter Description], [Supporting Parameters]
		FROM	(SELECT	'!~~~ Version ~~~~!' as [Parameter Name],'Information' as [Data Type],'0.0' as [Default Value],'Last Updated - 15/May/2019' as [Parameter Description], 'https://github.com/imajaydwivedi/SQLDBA-SSMS-Solution' as [Supporting Parameters]
					--
				UNION ALL
					--
				SELECT	'@p_Help' as [Parameter Name],'BIT' as [Data Type],'0' as [Default Value],'Displays this help message.' as [Parameter Description], '' as [Supporting Parameters]
					--
				UNION ALL
					--
				SELECT	'@p_SpId','INT',NULL,'Session ID to be killed, or for which rollback status check is required.', '[@p_RollbackStatus] [,@p_Verbose]' as [Supporting Parameters]
					--
				UNION ALL
					--
				SELECT	'@p_AddAuthorizedSessionKiller','BIT','0','Mention @p_LoginName (& @p_DbName is available but not required) along with this parameter to Add Exception as Authorized Killers of session requests.', '@p_LoginName [,@p_DbName] [,@p_Verbose] ' as [Supporting Parameters]
				--
				UNION ALL
					--
				SELECT	'@p_DbName','VARCHAR(125)',NULL,'Database name for which either the session are to be killed, or Exception has to be added.', '{@p_Force | @p_AddAuthorizedSessionKiller}' as [Supporting Parameters]
				--
				UNION ALL
					--
				SELECT	'@p_LoginName','VARCHAR(125)',NULL,'Login name for which either the session are to be killed, or Exception has to be added.', '{@p_Force | @p_AddAuthorizedSessionKiller} [,@p_DbName] [,@p_Verbose]' as [Supporting Parameters]
				--
				UNION ALL
					--
				SELECT	'@p_RollbackStatus','BIT','0','Is used to check rollback status of previous killed session id.', '@p_SpId [,@p_Verbose]' as [Supporting Parameters]
				--
				UNION ALL
					--
				SELECT	'@p_Force','BIT','0','Is used to kill all connections for @p_DbName and/or @p_LoginName.', '{@p_LoginName [,@p_DbName] | @p_DbName [,@p_LoginNam]} [,@p_Verbose]' as [Supporting Parameters]
				--
				UNION ALL
					--
				SELECT	'@p_Verbose','BIT','0','This present all background information that can be used to debug procedure working.', 'All parameters supported' as [Supporting Parameters]
				) AS Params; --([Parameter Name], [Data Type], [Default Value], [Parameter Description], [Supporting Parameters]);


		IF @p_Verbose = 1 
			PRINT	'/*	******************** End:	@p_Help = 1 *****************************/
';
	END

	IF @p_SpId IS NOT NULL
	BEGIN
		IF @p_Verbose = 1
			PRINT 'Begin - [@p_SpId IS NOT NULL]';

		IF NOT EXISTS(SELECT * FROM sys.dm_exec_sessions s where s.session_id = @p_SpId)
		BEGIN
			SET @_errorMSG = 'Session id (@p_SpId) '+cast(@p_SpId as varchar(10))+' no longer exists. No action required.';
			IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
				EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
			ELSE
				EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
		END

		IF @_isAuthorizedSessionKiller = 1 OR @_isKillerSameAsKilled = 1 OR @_isKillerDbOwner = 1 OR @_isKillerSysAdmin = 1
		BEGIN
			IF @p_RollbackStatus = 1
				SET @_SQLString = N'KILL '+CAST(@p_SpId AS VARCHAR(10))+' WITH STATUSONLY;';  
			ELSE
				SET @_SQLString = N'KILL '+CAST(@p_SpId AS VARCHAR(10));  

			BEGIN TRY
				EXEC (@_SQLString);
				PRINT 'Session Id '+CAST(@p_SpId AS VARCHAR(10))+' has been killed. To check rollback status, kindly execute below code:-'+CHAR(10)+'EXEC sp_kill @p_SpId = '+CAST(@p_SpId AS VARCHAR(10))+', @p_RollbackStatus = 1;';
			END TRY
			BEGIN CATCH
				SELECT @_errorMSG = ERROR_MESSAGE(), @_errorNumber = ERROR_NUMBER();

				IF @_errorNumber = 6106
					PRINT @_errorMSG;
				ELSE
				BEGIN
					IF (select CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),charindex('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)))-1) AS INT)) >= 12
						EXECUTE sp_executesql N'THROW 50000,@_errorMSG,1',N'@_errorMSG VARCHAR(200)', @_errorMSG;
					ELSE
						EXECUTE sp_executesql N'RAISERROR (@_errorMSG, 16, 1)', N'@_errorMSG VARCHAR(200)', @_errorMSG;
				END
			END CATCH
		END

		IF @p_Verbose = 1
			PRINT 'End - [@p_SpId IS NOT NULL]';
	END
	
END	 -- Proc Body
GO

/*
GRANT EXECUTE ON OBJECT::dbo.sp_Kill TO [public]
GO

EXEC sp_ms_marksystemobject 'sp_Kill'
go

CREATE CERTIFICATE [CodeSigningCertificate]
	ENCRYPTION BY PASSWORD = 'YourDummyPasswordHere'
	WITH EXPIRY_DATE = '2099-01-01'
		,SUBJECT = 'DBA Code Signing Cert'
GO

CREATE LOGIN [CodeSigningLogin] FROM CERTIFICATE [CodeSigningCertificate];
GO
--EXEC master..sp_addsrvrolemember @loginame = N'CodeSigningLogin', @rolename = N'sysadmin'
--GO
GRANT VIEW SERVER STATE TO [CodeSigningLogin]
GO
GRANT ALTER ANY CONNECTION TO [CodeSigningLogin]
GO
USE DBA;
CREATE USER [CodeSigningLogin] FOR LOGIN [CodeSigningLogin]
GO
EXEC sp_addrolemember @rolename = 'db_owner', @membername = 'CodeSigningLogin'  
GO

ADD SIGNATURE TO [dbo].[sp_Kill]
	BY CERTIFICATE [CodeSigningCertificate]
	WITH PASSWORD = 'YourDummyPasswordHere'
GO

*/

--SELECT * FROM DBA.dbo.AuthorizedSessionKiller