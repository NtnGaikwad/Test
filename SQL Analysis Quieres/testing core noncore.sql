USe Registry
GO
PRINT 'CREATING STORED PROCEDURE [sproc_GetUsersProjectAndActivityList]'
GO

ALTER PROCEDURE [dbo].sproc_GetUsersProjectAndActivityList						
						@RootOrganizationID INTEGER,
						@UserID INTEGER,
						@StartDate DateTime, 
						@LastSyncStartDate DateTime= NULL, 
						@EndDate DateTime = NULL,
						@LastSyncEndDate DateTime = NULL,
						@SyncTimeStamp   TIMESTAMP =0x,
						@AppMapSyncTimeStamp   TIMESTAMP =0x,
						@PurposeSyncTimeStamp   TIMESTAMP =0x,
						@WFMSyncTimeStamp   TIMESTAMP =0x,
						@WFOSyncTimeStamp   TIMESTAMP =0x,
						@TMSyncTimeStamp   TIMESTAMP =0x,
						@TDMSyncTimeStamp   TIMESTAMP =0x,
						@GetWFONTSK BIT=0x,
						@PlatformType SMALLINT,
						@WorkStationName VARCHAR(100),
						@MacID VARCHAR(100)						
						WITH ENCRYPTION				
AS
BEGIN
	SET NOCOUNT ON
DECLARE @SyncTimeStampOut TIMESTAMP,
			@AppMapSyncTimeStampOut  TIMESTAMP,
			@bPurposeListIsSame BIT,
			@OutPurposeSyncTimeStamp    TIMESTAMP,
			@TrackOption VARCHAR(25),
			@LogOption VARCHAR(25),
			@nTrackOption SMALLINT,
			@nLogOption SMALLINT,
			@WFMSyncTimeStampOut TIMESTAMP,
			@WFOSyncTimeStampOut TIMESTAMP,
			@TMSyncTimeStampOut TIMESTAMP,
			@TDMSyncTimeStampOut TIMESTAMP,
			@PurposeRowCount SMALLINT,
			@Today DateTime,
			@DoNotProcessThisrequest BIT,
			@LastSyncTime DateTime,
			@UserLastSync INT,
			@MachineID INT,
			@MaxTry SMALLINT,
			@TryCnt SMALLINT,			
			@DesignationCode INT
		
		DECLARE @ErrorMessage NVARCHAR(4000),
			@ErrorSeverity INT,  
			@ErrorState INT,  
			@ErrorNo INT 
			SET @MaxTry=3
			SET @TryCnt =0
			SET @ErrorNo=0

			SELECT @StartDate = CAST(@StartDate AS DATE),
		   @LastSyncStartDate =CAST(@LastSyncStartDate AS DATE),
		   @EndDate = CAST(@EndDate AS DATE),
		   @LastSyncEndDate= CAST(@LastSyncEndDate AS DATE),
		   @Today =CAST(GETDATE() AS DATE),@MachineID = -1
	
			SET @TryCnt =0
			WHILE @TryCnt < @MaxTry
			BEGIN
				BEGIN TRY
					SET @ErrorNo =0
					IF @MachineID = -1
					BEGIN
						 SELECT @MachineID = MM.ID
						FROM Registry..MachineMaster  MM 
						WHERE MM.RootOrganizationID= @RootOrganizationId AND MM.Machine = @WorkStationName +'|'+ @MacID

					END

					IF(@MachineID=-1 or @MachineID is null)
					BEGIN	
						SELECT @MachineID = ISNULL(MAX(ID),0)+1  
						FROM Registry..MachineMaster 
						WHERE RootOrganizationId=@RootOrganizationId
		
						INSERT INTO Registry..MachineMaster (ID,RootOrganizationId,Machine, PlatformType)
						VALUES(@MachineID,@RootOrganizationId,@WorkStationName +'|'+ @MacID, @PlatformType)
					END
				END TRY
				BEGIN CATCH
		
					SELECT   @ErrorSeverity = ERROR_SEVERITY(),  @ErrorState = ERROR_STATE() ,
							 @ErrorNo=ERROR_NUMBER() ,
							 @ErrorMessage = 'ERR_NO: ' + CONVERT(VARCHAR(20),ERROR_NUMBER()) + ', ERR_MSG: '  + ERROR_MESSAGE() + ', LINE: '  + CONVERT(VARCHAR(10),ERROR_LINE())

					SET @TryCnt = @TryCnt + 1
					IF (@ErrorNo = 2627 OR @ErrorNo = 2601) and @TryCnt < @MaxTry
					BEGIN
						SET @MachineID = -1
						continue;				 
					END
					ELSE
					BEGIN
					 RAISERROR (@ErrorMessage, -- Message text. 
								@ErrorSeverity, -- Severity.  
								@ErrorState -- State.  
								)  
					END 
				END CATCH	
				BREAK
				SET @TryCnt = 3
			END
			--Optimization logic start
			SET @DoNotProcessThisrequest = 1
			if(@SyncTimeStamp  =0x OR @AppMapSyncTimeStamp   =0x OR @PurposeSyncTimeStamp   =0x OR
						@WFMSyncTimeStamp    =0x OR @WFOSyncTimeStamp  =0x OR ( @TMSyncTimeStamp   =0x  and @PurposeSyncTimeStamp   =0x ))
			BEGIN
				SET @DoNotProcessThisrequest = 0
			END
			ELSE
			BEGIN	
				SELECT @LastSyncTime = U.UserLastSyncDt  FROM Registry..UserMachineFMDSyncInfo U 
				WHERE U.RootOrganizationId  = @RootOrganizationID AND U.UserID=@UserID and U.MachineID = @MachineID				
				If @@ROWCOUNT = 0
				BEGIN
					Set @LastSyncTime =DATEADD(DAY,-8,GETUTCDATE())
					INSERT INTO Registry..UserMachineFMDSyncInfo([RootOrganizationId],[UserID],[MachineID],	[UserLastSyncDt])
					VALUES( @RootOrganizationID,@UserID,@MachineID,@LastSyncTime)
				END			
				SET @UserLastSync = DATEDIFF(minute,@LastSyncTime,GETUTCDATE())
				
				--SELECT @UserLastSync ,@LastSyncTime,GETUTCDATE()
				IF 	@UserLastSync >=1440
				BEGIN
					SET @DoNotProcessThisrequest = 0
				END
				ELSE				
				BEGIN	
					SET @DoNotProcessThisrequest=(SELECT 0 FROM Registry..UserFMDSyncInfo U JOIN Registry..UserMachineFMDSyncInfo UM ON U.RootOrganizationId = UM.RootOrganizationId AND U.UserID = UM.UserID AND UM.MachineID = @MachineID
					WHERE U.RootOrganizationId  = @RootOrganizationID AND U.UserID=@UserID 
					AND ( U.ActivityModifiedDt> UM.UserLastSyncDt OR U.ApplicationModifiedDt> UM.UserLastSyncDt OR U.ProjectModifiedDt > UM.UserLastSyncDt OR U.TaskModifiedDt > UM.UserLastSyncDt OR U.WorkFlowModifiedDt > UM.UserLastSyncDt ))
					
					SET @DoNotProcessThisrequest= ISNULL(@DoNotProcessThisrequest,1)				
				END
			END

			--PRINT @DoNotProcessThisrequest
			SELECT @TrackOption ='ALL' , @LogOption= 'BASEURL'  
			SET @nTrackOption =ISNULL((SELECT CAST(ParameterValue as SMALLINT) 
							FROM Registry..Parameters 
							WHERE RootOrganizationId  = @RootOrganizationID AND ParameterName ='AgentBrowserTrackOption'),2)
			SET @nTrackOption =ISNULL(@nTrackOption,2)
	
			SET @nLogOption =ISNULL((SELECT CAST(ParameterValue as SMALLINT) 
									FROM Registry..Parameters 
									WHERE RootOrganizationId  = @RootOrganizationID AND ParameterName ='AgentBrowserLogOption'),0)
			SET @nLogOption =ISNULL(@nLogOption,0)
			SELECT @TrackOption =(CASE WHEN @nTrackOption= 0 THEN 'NONE' 
										WHEN @nTrackOption= 1 THEN 'SELECTED' 
										WHEN @nTrackOption= 2 THEN 'ALL' 
										ELSE 'ALL' END),
					@LogOption =(CASE WHEN @nLogOption= 0 THEN 'BASEURL' 
										WHEN @nLogOption= 1 THEN 'FULLURL'
										WHEN @nLogOption= 2 THEN 'FULLURL_ALL'  
										ELSE 'BASEURL' END)
							  
			--SET @DoNotProcessThisrequest=1
			if @DoNotProcessThisrequest = 1
			BEGIN
					--Project List
					SELECT -9999 ProjectID,  '' ProjectName, @Today  StartDate, @Today  EndDate ,0 IsDefaultTeam , -9999 TeamID ,'' TeamPath , 0 IsProcessed, CAST(0 AS TINYINT) OT ,-9999 ParentTeamID, '' TaskName, 
					@Today TaskStartDate, @Today TaskEndDate,  @Today VirtualTaskEndDate, @Today TaskPlannedStartDate, @Today TaskPlannedEndDate,
					9999 ID, 0  EffortEstimated, 0 EffortTotal, 0 IsDeleted, null FirstWorkedOn, null LastWorkedOn

					--APM
					SELECT -1 RootOrganizationId , -9999 PurposeID,-9999 TeamID ,-9999 ParentActivityID ,-9999 ActivityID ,-9999 OrderID,1 IsDeleted,'' Title, '' FullTitle, @Today DateDeleted,0x ChangeTimeStamp,0 IsOfflineActivity,0 Attributes,0 IsSystemDefined, 0 IsConfigurable
						
					--WinRules				
					SELECT -9999 ParentActivityID, -9999 ActivityID, '' AppName, '' AppVersion, 0 DefaultPurpose, '' WebApp, 0 IsAllowedOverride,0  URLMatchingFlag,0 AppNameLen, 1 IsDeleted
					
					--WebRules
					SELECT -9999 ParentActivityID, -9999 ActivityID, '' AppName, '' AppVersion, 0 DefaultPurpose, '' WebApp, 0 IsAllowedOverride,0  URLMatchingFlag,0 AppNameLen, 1 IsDeleted
					
			
					SELECT @TrackOption TrackOption, @LogOption LogOption

					--TimeStamp
					SELECT ISNULL(@SyncTimeStamp,0x0) ActivitySyncTimeStamp, ISNULL(@AppMapSyncTimeStamp,0x0) AppMapSyncTimeStamp,
					 ISNULL(@PurposeSyncTimeStamp,0x0) PurposeSyncTimeStamp,		 
					 ISNULL(@WFMSyncTimeStamp,0x0) WFMSyncTimeStamp,ISNULL(@WFOSyncTimeStamp,0x0) WFOSyncTimeStamp,
					  ISNULL(@TMSyncTimeStamp,0x0) TMSyncTimeStamp,ISNULL(@TDMSyncTimeStamp,0x0) TDMSyncTimeStamp

					--Workflow
					SELECT -9999 PurposeID,-9999 TeamID ,-9999 WFPID ,-9999 WFID ,-9999 OrderID,1 IsDeleted,'' Title, @Today DateDeleted,0 Attributes,0 IsSystemDefined, 0 IsConfigurable,0 TAT
					RETURN 0
			END
			--Optimization logic end

	CREATE TABLE #Purpose (ProjectID INTEGER NOT NULL,
			ProjectName NVARCHAR(512) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
			StartDate DateTime NOT NULL,
			EndDate DateTime NULL,
			IsDefaultTeam Bit NOT NULL DEFAULT(0),
			TeamID INTEGER NOT NULL DEFAULT(-1),
			TeamPath NVARCHAR(4000) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
			IsProcessed TINYINT NULL,
			ChangeTimeStamp VARBINARY(8),
			OT TINYINT DEFAULT(0),
			ParentTeamID INTEGER NOT NULL DEFAULT(-1),
			TaskName NVARCHAR(512) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
			TaskStartDate DateTime NULL,
			TaskEndDate DateTime NULL,
			VirtualTaskEndDate DateTime NULL,
			STUID INTEGER NOT NULL)

	CREATE INDEX #Purpose_IDEX On #Purpose(ProjectID,TeamID)

	CREATE TABLE #LastPurpose (ProjectID INTEGER NOT NULL,
			ProjectName NVARCHAR(512) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
			StartDate DateTime NOT NULL,
			EndDate DateTime NULL,
			IsDefaultTeam Bit NOT NULL DEFAULT(0),
			TeamID INTEGER NOT NULL DEFAULT(-1),
			TeamPath NVARCHAR(4000) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
			IsProcessed TINYINT NULL,
			ChangeTimeStamp VARBINARY(8),
			OT TINYINT DEFAULT(0),
			ParentTeamID INTEGER NOT NULL DEFAULT(-1),
			TaskName NVARCHAR(512) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
			TaskStartDate DateTime NULL,
			TaskEndDate DateTime NULL,
			VirtualTaskEndDate DateTime NULL,
			STUID INTEGER NOT NULL)
	
	CREATE INDEX #LastPurpose_IDEX On #LastPurpose(ProjectID,TeamID)

	CREATE TABLE #Activity (
		RootOrganizationId INTEGER NOT NULL,
		PurposeID INTEGER NOT NULL,
		TeamID INTEGER NOT NULL,		
		ParentActivityID INTEGER NOT NULL,
		ActivityID INTEGER NOT NULL,
		OrderID INTEGER NOT NULL,
		IsDeleted Bit NOT NULL,
		Title NVARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
		FullTitle NVARCHAR(4000) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
		DateDeleted SMALLDATETIME NULL,
		ChangeTimeStamp VARBINARY(8),
		IsOfflineActivity TINYINT,
		Attributes SMALLINT  NOT NULL DEFAULT(0),
		IsNewProject BIT NOT NULL DEFAULT(0),
		IsSystemDefined BIT NOT NULL,
		IsConfigurable BIT NOT NULL)
	
	--CREATE INDEX #Activity_IDEX On #Activity(RootOrganizationId,ParentActivityID,ActivityID)
	
CREATE TABLE #Workflow (
		RootOrganizationId INTEGER NOT NULL,
		PurposeID INTEGER NOT NULL,
		TeamID INTEGER NOT NULL,		
		WFID INTEGER NOT NULL,
		WFPID INTEGER NOT NULL,
		OrderID SMALLINT NOT NULL,
		IsDeleted Bit NOT NULL,
		Title NVARCHAR(4000) COLLATE DATABASE_DEFAULT NOT NULL DEFAULT(''),
		DateDeleted SMALLDATETIME NULL,		
		Attributes SMALLINT  NOT NULL DEFAULT(0),
		TAT INTEGER  NOT NULL DEFAULT(0),
		IsNewProject BIT NOT NULL DEFAULT(0),
		IsSystemDefined BIT NOT NULL,
		IsConfigurable BIT NOT NULL,
		WFMChangeTimeStamp VARBINARY(8),
		WFOChangeTimeStamp VARBINARY(8))

		CREATE TABLE #Task (
		RootOrganizationId INTEGER NOT NULL,
		PurposeID INTEGER NOT NULL,
		TeamID INTEGER NOT NULL,	
		NodeType TINYINT NOT NULL DEFAULT(6),
		NodeID INTEGER NOT NULL,
        ID BIGINT NOT NULL,
        EffortEstimated REAL NOT NULL DEFAULT(0),
        EffortTotal REAL NOT NULL DEFAULT(0),
        IsDeleted BIT NOT NULL DEFAULT(0),      
		IsNewProject BIT NOT NULL DEFAULT(0),
		TMChangeTimeStamp VARBINARY(8),
		TDMChangeTimeStamp VARBINARY(8),
		FirstWorkedOn DATETIME NULL,
		LastWorkedOn DATETIME NULL,
		TaskPlannedStartDate DateTime NULL,
		TaskPlannedEndDate DateTime NULL)

	CREATE TABLE #UniqueActivity(
		RootOrganizationId INTEGER NOT NULL,
		ParentActivityID INTEGER NOT NULL,
		ActivityID INTEGER NOT NULL)

	CREATE INDEX #UniqueActivity_IDEX On #UniqueActivity(RootOrganizationId,ParentActivityID,ActivityID)

	CREATE TABLE #OldUniqueActivity(
		RootOrganizationId INTEGER NOT NULL,
		ParentActivityID INTEGER NOT NULL,
		ActivityID INTEGER NOT NULL)
	
	CREATE INDEX #OldUniqueActivity_IDEX On #OldUniqueActivity(RootOrganizationId,ParentActivityID,ActivityID)


	CREATE TABLE #AppRules (ParentActivityID	SMALLINT	NOT NULL,
							ActivityID	SMALLINT	NOT NULL,
							AppName NVARCHAR(255)	COLLATE DATABASE_DEFAULT NOT NULL,
							AppVersion	VARCHAR(100)	COLLATE DATABASE_DEFAULT NOT NULL,  
							DefaultPurpose INTEGER NOT NULL,
							WebApp	NVARCHAR(100)	COLLATE DATABASE_DEFAULT NOT NULL,
							IsAllowedOverride	BIT	NOT NULL,
							URLMatchingFlag	INTEGER	NOT NULL, 
							AppNameLen   INTEGER	NOT NULL,
							IsDeleted	BIT	NOT NULL)

	
	INSERT INTO #Purpose
	EXEC dbo.sproc_GetUsersProjectListEX1 @RootOrganizationId, @UserID, @StartDate, @EndDate , @PlatformType,@GetWFONTSK
	SELECT @OutPurposeSyncTimeStamp   = MAX(ChangeTimeStamp) FROM #Purpose
	SET @PurposeRowCount=@@ROWCOUNT

	IF @GetWFONTSK = 1	
	BEGIN
		INSERT INTO #Task
		SELECT T.RootOrganizationId,P.ProjectID,P.ParentTeamID,T.NodeType,T.NodeID,T.ID,TD.EffortEstimated,T.EffortTotal,T.Isdeleted,
		0, T.[ChangeTimeStamp], 0x0,NULL,NULL,TD.StartDate,TD.EndDate
		 FROM dbo.UserTasksMaster T 
		 INNER JOIN [dbo].[TaskDetails] TD ON T.RootOrganizationId = TD.RootOrganizationId AND T.NodeID = TD.ID and T.NodeType = 6
		 INNER JOIN #Purpose P ON T.RootOrganizationId=@RootOrganizationId AND T.UserID= @UserId AND T.NodeID= P.TeamID and T.NodeType= P.OT 
		 
		 
		UPDATE T
		SET T.IsNewProject = 1	
		FROM #Task T INNER JOIN #Purpose P ON T.PurposeID = P.ProjectID and T.TeamID = P.TeamID 
		WHERE (@PurposeSyncTimeStamp = 0x0) OR (@PurposeSyncTimeStamp <> 0x0 AND P.ChangeTimeStamp > @PurposeSyncTimeStamp) 	

		Update T
		SET T.FirstWorkedOn = TDM.FirstWorkedOn,
			T.LastWorkedOn= TDM.LastWorkedOn,
			T.TDMChangeTimeStamp = TDM.ChangeTimeStamp
		FROM #Task T INNER JOIN (SELECT TD.RootOrganizationId ,TD.ID, MIN(TD.FirstWorkedOn) FirstWorkedOn,MAX(TD.LastWorkedOn) LastWorkedOn,MAx(TD.ChangeTimeStamp)ChangeTimeStamp
		FROM #Task TT INNER JOIN dbo.UserTaskDetailsMaster TD ON TT.RootOrganizationId=TD.RootOrganizationId AND TT.ID = TD.ID
		Group by TD.RootOrganizationId ,TD.ID) TDM  ON T.RootOrganizationId=TDM.RootOrganizationId AND T.ID = TDM.ID
	END
		
	IF  @PurposeRowCount = 0 
	BEGIN
		SELECT -9999 ProjectID,  '' ProjectName, @Today  StartDate, @Today  EndDate ,0 IsDefaultTeam , -9999 TeamID ,'' TeamPath , 0 IsProcessed, CAST(0 AS TINYINT) OT ,-9999 ParentTeamID, '' TaskName, 
		@Today TaskStartDate, @Today TaskEndDate,  @Today VirtualTaskEndDate, @Today TaskPlannedStartDate, @Today TaskPlannedEndDate,
		9999 ID, 0  EffortEstimated, 0 EffortTotal, 0 IsDeleted, null FirstWorkedOn, null LastWorkedOn
	END
	ELSE
	BEGIN
		
		SELECT P.ProjectID, P.ProjectName , P.StartDate , P.EndDate, P.IsDefaultTeam , P.TeamID ,P.TeamPath, P.IsProcessed, P.OT, 
			  P.ParentTeamID, P.TaskName, P.TaskStartDate, P.TaskEndDate, P.VirtualTaskEndDate, T.TaskPlannedStartDate, T.TaskPlannedEndDate,
			  ISNULL(P.STUID,-1) ID,ISNULL(T.EffortEstimated,0) EffortEstimated,ISNULL(T.EffortTotal,0) EffortTotal,ISNULL(T.IsDeleted,0) IsDeleted, T.FirstWorkedOn, T.LastWorkedOn
		 FROM #Purpose P LEFT JOIN #Task T  ON P.ProjectID = T.PurposeID and P.TeamID = T.NodeID 
	END

	IF(NOT @LastSyncStartDate IS NULL)
	BEGIN
		INSERT INTO #LastPurpose
		EXEC dbo.sproc_GetUsersProjectListEX1 @RootOrganizationId, @UserID, @LastSyncStartDate, @LastSyncEndDate, @PlatformType	,@GetWFONTSK
	END
		
	DELETE P	
	FROM #Purpose P JOIN #LastPurpose LP on P.ProjectID = LP.ProjectID AND P.TeamID = LP.TeamID 
	
	INSERT INTO #Purpose
	SELECT * FROM #LastPurpose 
	
	IF @GetWFONTSK = 1
	BEGIN
		INSERT INTO #Workflow
		SELECT AM.RootOrganizationID, LP.ProjectID,LP.TeamID, AM.ID, AM.ParentID WFPID, AP.OrderID, AP.IsDeleted, AM.Title,			
				AP.DeletedDate,AP.Attributes,AP.TAT,0, AP.IsSystemDefined,AP.IsConfigurable,AM.ChangeTimeStamp,AP.ChangeTimeStamp
		FROM  Registry..WorkflowMaster AM JOIN Registry..WorkflowObject  AP ON AP.RootOrganizationID=AM.RootOrganizationId and AP.WFID = AM.ID
			JOIN #Purpose LP ON AP.RootOrganizationID=@RootOrganizationID AND ((LP.TeamID = AP.ObjectID AND AP.ObjectType= 3 AND LP.TeamID >0) OR (LP.ProjectID= AP.ObjectID AND AP.ObjectType= 2 AND LP.TeamID <0))
		WHERE AM.RootOrganizationID=@RootOrganizationID 
		--ORDER BY LP.ProjectID, LP.TeamID--, OrderID

		UPDATE A
		SET A.IsNewProject = 1	
		FROM #Workflow A INNER JOIN #Purpose P ON A.PurposeID = P.ProjectID and A.TeamID = P.TeamID AND P.OT < 3
		WHERE (@PurposeSyncTimeStamp = 0x0) OR (@PurposeSyncTimeStamp <> 0x0 AND P.ChangeTimeStamp > @PurposeSyncTimeStamp) 
	END

	INSERT INTO #Activity
	SELECT AP.RootOrganizationID, LP.ProjectID,LP.TeamID, AP.ParentActivityID, AP.ActivityID, AP.OrderID, AP.IsDeleted, AG.Title,
			AG.TitleFullPath,
			AP.DeletedDate,AP.ChangeTimeStamp, AM.ActivityType IsOfflineActivity, AP.Attributes,0,AM.IsSystemDefined,AM.IsConfigurable 
	FROM Registry..ActivityObject AP JOIN Registry..ActivityGroup AG ON AP.RootOrganizationID=AG.RootOrganizationId
		AND  AP.ParentActivityID= AG.ParentID AND AP.ActivityID = AG.ID 
		JOIN Registry..ActivityMaster AM ON AG.RootOrganizationID=AM.RootOrganizationId and AG.ID = AM.ID
		JOIN #Purpose LP ON AP.RootOrganizationID=@RootOrganizationID AND ((LP.TeamID = AP.ObjectID AND AP.ObjectType= 3 AND LP.TeamID >0) OR (LP.ProjectID= AP.ObjectID AND AP.ObjectType= 2 AND LP.TeamID <0))
	WHERE AP.RootOrganizationID=@RootOrganizationID 
	AND (AP.PlatformType & @PlatformType) !=0
	AND LP.OT < 3
	--ORDER BY LP.ProjectID, LP.TeamID, AP.OrderID

	BEGIN TRY
		IF EXISTS(SELECT 1  FROM Registry..Parameters WHERE RootOrganizationId=@RootOrganizationId 
				AND ParameterName ='ActivityCoreNonCoreByDesignation' AND LTRIM(RTRIM(ParameterValue)) = '1')
		BEGIN
			SELECT @DesignationCode = ISNULL(UD.DesignationId,0)
			FROM Registry..UserDetails UD 
			WHERE UD.RootOrganizationId=@RootOrganizationId AND UD.UserID=@UserID
			IF EXISTS (SELECT 1 FROM Registry..ObjectActivityMapping OAM 
						WHERE  OAM.RootOrganizationId=@RootOrganizationId 
						AND OAM.ObjectID=@DesignationCode AND OAM.ObjectType = 8 AND OAM.IsDeleted=0)
			BEGIN

				UPDATE A
				SET A.Attributes = 0
				FROM #Activity A 

				UPDATE A
				SET A.Attributes = ISNULL(OAM.Attributes,0)
				FROM #Activity A LEFT JOIN Registry..ObjectActivityMapping OAM 
					ON OAM.RootOrganizationId=a.RootOrganizationId AND OAM.ObjectID=@DesignationCode AND OAM.ObjectType = 8
					AND OAM.ParentActivityID= a.ParentActivityID AND a.ActivityID = oam.ActivityID 
				WHERE OAM.IsDeleted=0
			END 			
		END
	END TRY
	BEGIN CATCH
		--ignore
	END CATCH

	UPDATE A
	SET A.IsNewProject = 1	
	FROM #Activity A INNER JOIN #Purpose P ON A.PurposeID = P.ProjectID and A.TeamID = P.TeamID AND P.OT < 3
	WHERE (@PurposeSyncTimeStamp = 0x0) OR (@PurposeSyncTimeStamp <> 0x0 AND P.ChangeTimeStamp > @PurposeSyncTimeStamp) --AND P.EndDate >  dbo.DateOnly(GETDATE())

	INSERT INTO #UniqueActivity
	SELECT DISTINCT RootOrganizationId, ParentActivityID, ActivityID
	FROM #Activity
	WHERE (ChangeTimeStamp > @SyncTimeStamp or @SyncTimeStamp IS NULL) OR (IsNewProject = 1)

	--IF  NOT EXISTS(SELECT 1 FROM #Activity WHERE (ChangeTimeStamp > @SyncTimeStamp or @SyncTimeStamp IS NULL)  OR (IsNewProject = 1))		
	IF @@ROWCOUNT = 0
	BEGIN
		SELECT -1 RootOrganizationId , -9999 PurposeID,-9999 TeamID ,-9999 ParentActivityID ,-9999 ActivityID ,-9999 OrderID,1 IsDeleted,'' Title, '' FullTitle, @Today DateDeleted,0x ChangeTimeStamp,0 IsOfflineActivity,0 Attributes,0 IsSystemDefined, 0 IsConfigurable
	END	
	ELSE
	BEGIN
		SELECT * FROM #Activity
		WHERE (ChangeTimeStamp > @SyncTimeStamp or @SyncTimeStamp IS NULL) OR (IsNewProject = 1)
		ORDER BY PurposeID, TeamID, OrderID
	END

	INSERT INTO #OldUniqueActivity
	SELECT DISTINCT RootOrganizationId, ParentActivityID, ActivityID
	FROM #Activity
	WHERE (@SyncTimeStamp IS NULL OR ChangeTimeStamp < @SyncTimeStamp ) AND (IsNewProject = 0) 
	
	SELECT @AppMapSyncTimeStampOut=MAX(AAM.ChangeTimeStamp)
	FROM #UniqueActivity A join ActivityApplication AAM 
		on A.RootOrganizationId =AAM.RootOrganizationId 
			AND A.ParentActivityID = AAM.ParentActivityID
			AND A.ActivityID= AAM.ActivityID
	WHERE A.RootOrganizationId  = @RootOrganizationID 
	AND (AAM.PlatformType & @PlatformType) !=0

	DELETE UA
	FROM #UniqueActivity UA join #OldUniqueActivity OUA on UA.RootOrganizationId =OUA.RootOrganizationId 
						AND UA.ParentActivityID =OUA.ParentActivityID 
						AND UA.ActivityID =OUA.ActivityID
		
	INSERT INTO #AppRules	
		SELECT A.ParentActivityID,A.ActivityID, AAM.AppName, AAM.AppVersion, ISNULL(AAM.DefaultPurpose,0) DefaultPurpose, ISNULL(AAM.WebApp,'')WebApp, ISNULL(AAM.CanOverride,1) IsAllowedOverride,
		ISNULL(AAM.UrlMatching,0) URLMatchingFlag,0 AppNameLen, AAM.IsDeleted IsDeleted
		FROM #OldUniqueActivity A join ActivityApplication AAM 
		ON 	A.RootOrganizationId =AAM.RootOrganizationId  
			AND A.ParentActivityID = AAM.ParentActivityID
			AND A.ActivityID= AAM.ActivityID
		WHERE A.RootOrganizationId  = @RootOrganizationID 
			AND ISNULL(AAM.IsApplication,1) = 1
			AND (AAM.PlatformType & @PlatformType) !=0
			AND (AAM.ChangeTimeStamp > @AppMapSyncTimeStamp or @AppMapSyncTimeStamp IS NULL)
	UNION ALL
		SELECT A.ParentActivityID,A.ActivityID, AAM.AppName, AAM.AppVersion, ISNULL(AAM.DefaultPurpose,0) DefaultPurpose, ISNULL(AAM.WebApp,'')WebApp, ISNULL(AAM.CanOverride,1) IsAllowedOverride,
		ISNULL(AAM.UrlMatching,0) URLMatchingFlag,0 AppNameLen , AAM.IsDeleted IsDeleted
		FROM #UniqueActivity A join ActivityApplication AAM 
		ON 	A.RootOrganizationId =AAM.RootOrganizationId  
			AND A.ParentActivityID = AAM.ParentActivityID
			AND A.ActivityID= AAM.ActivityID
		WHERE A.RootOrganizationId  = @RootOrganizationID 
			AND ISNULL(AAM.IsApplication,1) = 1
			AND (AAM.PlatformType & @PlatformType) !=0
	--ORDER BY A.ParentActivityID,A.ActivityID, AAM.AppName
	IF @@ROWCOUNT =0
	BEGIN
		SELECT -9999 ParentActivityID, -9999 ActivityID, '' AppName, '' AppVersion, 0 DefaultPurpose, '' WebApp, 0 IsAllowedOverride,0  URLMatchingFlag,0 AppNameLen, 1 IsDeleted
	END
	ELSE
	BEGIN
		SELECT * FROM #AppRules A
		ORDER BY A.ParentActivityID,A.ActivityID, A.AppName
	END
	
	DELETE FROM #AppRules 

	INSERT INTO #AppRules	
	SELECT A.ParentActivityID ParentActivityID,A.ActivityID ActivityID, AAM.AppName AppName, AAM.AppVersion AppVersion, ISNULL(AAM.DefaultPurpose,0) DefaultPurpose, ISNULL(AAM.WebApp,'')WebApp, ISNULL(AAM.CanOverride,1) IsAllowedOverride,
		ISNULL(AAM.URLMatching,0) URLMatchingFlag, LEN(AAM.AppName) AppNameLen , AAM.IsDeleted IsDeleted
		FROM #OldUniqueActivity A join ActivityApplication AAM 
		on A.RootOrganizationId =AAM.RootOrganizationId 
			AND A.ParentActivityID = AAM.ParentActivityID
			AND A.ActivityID= AAM.ActivityID
		WHERE A.RootOrganizationId  = @RootOrganizationID 
		AND AAM.IsApplication = 0
		AND (AAM.PlatformType & @PlatformType) !=0
		AND (AAM.ChangeTimeStamp > @AppMapSyncTimeStamp or @AppMapSyncTimeStamp IS NULL)
		--ORDER BY URLMatchingFlag, LEN(AAM.AppName) DESC, AAM.AppName DESC
	UNION ALL
		SELECT A.ParentActivityID ParentActivityID,A.ActivityID ActivityID, AAM.AppName AppName, AAM.AppVersion AppVersion, ISNULL(AAM.DefaultPurpose,0) DefaultPurpose, ISNULL(AAM.WebApp,'')WebApp, ISNULL(AAM.CanOverride,1) IsAllowedOverride,
		ISNULL(AAM.URLMatching,0) URLMatchingFlag, LEN(AAM.AppName) AppNameLen, AAM.IsDeleted IsDeleted
		FROM #UniqueActivity A join ActivityApplication AAM 
		on A.RootOrganizationId =AAM.RootOrganizationId 
			AND A.ParentActivityID = AAM.ParentActivityID
			AND A.ActivityID= AAM.ActivityID
		WHERE A.RootOrganizationId  = @RootOrganizationID 
		AND AAM.IsApplication = 0
		AND (AAM.PlatformType & @PlatformType) !=0
	--ORDER BY URLMatchingFlag, AppNameLen DESC, AppName DESC 
	IF @@ROWCOUNT =0
	BEGIN
		SELECT -9999 ParentActivityID, -9999 ActivityID, '' AppName, '' AppVersion, 0 DefaultPurpose, '' WebApp, 0 IsAllowedOverride,0  URLMatchingFlag,0 AppNameLen, 1 IsDeleted
	END
	ELSE
	BEGIN
		SELECT * FROM #AppRules A
		ORDER BY URLMatchingFlag, AppNameLen DESC, AppName DESC 
	END
	
	--Track Options 
	-- ALL, SELECTED, NONE
	-- LOG OPTION.
	-- BASEURL, FULLURL
	--SELECT @TrackOption ='ALL' , @LogOption= 'BASEURL'  
	--AgentBrowserTackOption ALL=2,SELECTED=1,NONE=0

--AgentBrowserLogOption BASEURL=0, FULLURL=1


	SELECT @TrackOption TrackOption, @LogOption LogOption
	
	SELECT @SyncTimeStampOut  = MAX(ChangeTimeStamp)
	FROM #Activity
		

	SELECT @WFMSyncTimeStampOut  = MAX(WFMChangeTimeStamp),@WFOSyncTimeStampOut= MAX(WFOChangeTimeStamp)
	FROM #Workflow
	
	SELECT @TMSyncTimeStampOut  = MAX(TMChangeTimeStamp),@TDMSyncTimeStampOut= MAX(TDMChangeTimeStamp)
	FROM #Task

	SELECT @SyncTimeStampOut ActivitySyncTimeStamp, 
		 CASE WHEN @AppMapSyncTimeStampOut is null THEN @AppMapSyncTimeStamp ELSE @AppMapSyncTimeStampOut END AppMapSyncTimeStamp,
		 @OutPurposeSyncTimeStamp PurposeSyncTimeStamp,		 
		 ISNULL(@WFMSyncTimeStampOut,0x0) WFMSyncTimeStamp,ISNULL(@WFOSyncTimeStampOut,0x0) WFOSyncTimeStamp,
		  ISNULL(@TMSyncTimeStampOut,0x0) TMSyncTimeStamp,ISNULL(@TDMSyncTimeStampOut,0x0) TDMSyncTimeStamp


	IF  NOT EXISTS(SELECT 1 FROM #Workflow 
	WHERE (WFMChangeTimeStamp > @WFMSyncTimeStamp or @WFMSyncTimeStamp IS NULL OR 
				WFOChangeTimeStamp > @WFOSyncTimeStamp or @WFOSyncTimeStamp IS NULL) OR (IsNewProject = 1))		
	--IF @@ROWCOUNT = 0
	BEGIN
		SELECT -9999 PurposeID,-9999 TeamID ,-9999 WFPID ,-9999 WFID ,-9999 OrderID,1 IsDeleted,'' Title, @Today DateDeleted,0 Attributes,0 IsSystemDefined, 0 IsConfigurable,0 TAT
	END	
	ELSE
	BEGIN
		SELECT PurposeID, TeamID , WFPID ,WFID ,OrderID, IsDeleted, Title, DateDeleted, Attributes,
		IsSystemDefined, IsConfigurable,TAT
		FROM #Workflow
		WHERE (WFMChangeTimeStamp > @WFMSyncTimeStamp or @WFMSyncTimeStamp IS NULL OR 
				WFOChangeTimeStamp > @WFOSyncTimeStamp or @WFOSyncTimeStamp IS NULL) OR (IsNewProject = 1)
		ORDER BY PurposeID, TeamID, OrderID
	END

	UPDATE U
	SET U.UserLastSyncDt = GETUTCDATE()
	FROM Registry..UserMachineFMDSyncInfo U 
	WHERE U.RootOrganizationId  = @RootOrganizationID AND U.UserID=@UserID and U.MachineID = @MachineID

	UPDATE U
	SET U.UserLastSyncDt = GETUTCDATE()
	FROM Registry..UserFMDSyncInfo U 
	WHERE U.RootOrganizationId  = @RootOrganizationID AND U.UserID=@UserID 

	DROP TABLE #Purpose
	DROP TABLE #LastPurpose
	DROP TABLE #Activity
	DROP TABLE #UniqueActivity
	DROP TABLE #OldUniqueActivity
	DROP TABLE #AppRules 
	DROP TABLE #Workflow
	DROP TABLE #Task
	RETURN 0
END

GO