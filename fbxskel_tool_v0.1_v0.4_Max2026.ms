(
-- FBXSKEL TOOL
-- For RE Engine fbxskel.2, fbxskel.3 and fbxskel.5 files in 3ds Max
-- v0.1 pose-preserve + v0.4 full-rebuild - 3ds Max 2026 edition
-- By alphaZomega and che
-- Original binary layout and coordinate conversion are preserved.

global REEngineFBXSkel

-- Close a previous dialog before redefining the rollout. Max 2026 keeps the
-- old rollout instance alive when a script is evaluated repeatedly.
try
(
    if REEngineFBXSkel != undefined do destroyDialog REEngineFBXSkel
)
catch ()

fn ReadInt64 bstream = (
    ReadLongLong bstream
)

fn ReadUInt64 bstream = (
    -- ReadLongLong is already an Integer64 in current 3ds Max releases.
    -- The fbxskel offsets/counts used here stay inside its signed range.
    ReadLongLong bstream
)

fn ReadInt bstream = (
    value = ReadLong bstream;
    return value;
)

fn ReadUInt bstream = (
    value = ReadLong bstream #unsigned;
    return value;
)

fn ReadSShort bstream = (
    value = ReadShort bstream;
    return value;
)

fn ReadUShort bstream = (
    value = ReadShort bstream #unsigned;
    return value;
)

fn ReadSByte bstream = (
    value = ReadByte bstream;
    return value;
)

fn ReadUByte bstream = (
    value = ReadByte bstream #unsigned;
    return value;
)

fn fskip bstream count = (
    fseek bstream count #seek_cur;
)

fn ReadWString bstream = (
	local str = ""
	local c = ReadUShort bstream
	while c != 0 do
    (
		str += bit.intAsChar(c)
		c = ReadUShort bstream
	)
	str
)

fn writeUnicodeString &bstream input = (
	for charIndex = 1 to input.count do (
		writeByte bstream (bit.charAsInt input[charIndex]) #unsigned
		writebyte bstream 0
	)
	writeshort bstream 0
)

fn WriteInt64 bstream value = (
	WriteLongLong bstream (value as integer64)
)

fn REEngineFBXSkelCloseStream stream = (
	if stream != undefined do
	(
		try (fclose stream) catch (undefined)
	)
)

fn REEngineFBXSkelVersionSupported version = (
	(findItem #(2, 3, 5) (version as integer)) != 0
)

fn REEngineFBXSkelNameOnly rawName = (
    local nameParts = filterString rawName ":"
    if nameParts.count > 1 then nameParts[nameParts.count] else rawName
)

fn REEngineFBXSkelCommitTemp tempPath targetPath = (
    local backupPath = targetPath + ".bak." + ((timestamp()) as string)
    local oldTargetMoved = false
    local committed = false

    try
    (
        if doesFileExist targetPath do
        (
            if doesFileExist backupPath do
                throw "A temporary backup path already exists. Try the export again."
            renameFile targetPath backupPath
            if doesFileExist targetPath or not (doesFileExist backupPath) do
                throw "The existing target file could not be moved out of the way."
            oldTargetMoved = true
        )

        renameFile tempPath targetPath
        if doesFileExist tempPath or not (doesFileExist targetPath) do
            throw "The completed temporary file could not be committed."

        committed = true
        if oldTargetMoved and doesFileExist backupPath do
            try (deleteFile backupPath) catch ()
    )
    catch
    (
        if not committed do
        (
            if oldTargetMoved and doesFileExist targetPath do
                try (deleteFile targetPath) catch ()
            if oldTargetMoved and doesFileExist backupPath and not (doesFileExist targetPath) do
                try (renameFile backupPath targetPath) catch ()
        )
    )

    committed
)

fn REEngineFBXSkelIsBoneNode nodeValue = (
    if nodeValue == undefined or not (isValidNode nodeValue) then
        false
    else
    (
        local nodeSuperClass = superclassof nodeValue
        nodeSuperClass == helper or nodeSuperClass == BoneGeometry
    )
)

fn REEngineFBXSkelCollectBoneTrees selectedNodes = (
    local collectedBones = #()
    local pendingNodes = for nodeValue in selectedNodes collect nodeValue

    while pendingNodes.count > 0 do
    (
        local nodeValue = pendingNodes[pendingNodes.count]
        deleteItem pendingNodes pendingNodes.count

        if nodeValue != undefined and isValidNode nodeValue do
        (
            if REEngineFBXSkelIsBoneNode nodeValue and (findItem collectedBones nodeValue) == 0 do
                append collectedBones nodeValue
            for childNode in nodeValue.children do
                append pendingNodes childNode
        )
    )
    collectedBones
)

fn REEngineFBXSkelExportPosePreserve sourcePath changedBones = (
    local sourceStream = undefined
    local outputStream = undefined
    local outputPath = sourcePath + ".NewSkel"
    local tempPath = outputPath + ".tmp." + ((timestamp()) as string)

    try
    (
        sourceStream = fopen sourcePath "rb"
        if sourceStream == undefined do throw "The selected source fbxskel could not be opened."

        local version = ReadUInt sourceStream
        if (ReadUInt64 sourceStream) != 1852599155 do throw "Select a valid source fbxskel file."
        if not (REEngineFBXSkelVersionSupported version) do
            throw ("Unsupported source fbxskel version: " + (version as string))

        fseek sourceStream 0x10 #seek_set
        local bonesStartOffs = ReadUInt64 sourceStream
        fskip sourceStream 8
        local boneCount = ReadUInt64 sourceStream
        if boneCount < 1 do throw "The selected source fbxskel contains no bones."

        local namesOffs = #()
        local namesList = #()
        fseek sourceStream bonesStartOffs #seek_set
        for i = 1 to boneCount do
        (
            append namesOffs (ReadUInt64 sourceStream)
            fskip sourceStream 56
        )
        for i = 1 to boneCount do
        (
            fseek sourceStream namesOffs[i] #seek_set
            append namesList (ReadWString sourceStream)
        )

        REEngineFBXSkelCloseStream sourceStream
        sourceStream = undefined

        if doesFileExist tempPath do deleteFile tempPath
        if doesFileExist tempPath do throw "A previous pose-export temporary file could not be removed."
        (dotNetClass "System.IO.File").Copy sourcePath tempPath true
        if not (doesFileExist tempPath) do throw "The source fbxskel could not be copied for pose export."
        local tempInfo = dotNetObject "System.IO.FileInfo" tempPath
        tempInfo.IsReadOnly = false

        outputStream = fopen tempPath "rb+"
        if outputStream == undefined do throw "The pose-export copy could not be opened for updating."

        local axisMatrix = matrix3 [1,0,0] [0,0,-1] [0,1,0] [0,0,0]
        local changedCount = 0
        local skippedNames = #()
        local translationOffset = if version == 5 then 32 else 16

        for boneNode in changedBones do
        (
            if boneNode.parent != undefined then
            (
                local subBoneName = REEngineFBXSkelNameOnly boneNode.name
                local parentBoneName = REEngineFBXSkelNameOnly boneNode.parent.name
                local subBoneIndex = findItem namesList subBoneName
                local parentBoneIndex = findItem namesList parentBoneName

                if subBoneIndex > 0 and parentBoneIndex > 0 then
                (
                    local parentMatrix = (copy boneNode.parent.transform) * axisMatrix
                    local boneMatrix = (copy boneNode.transform) * axisMatrix
                    local localPosition = (boneMatrix * (inverse parentMatrix)).row4
                    local recordOffset = bonesStartOffs + ((subBoneIndex - 1) * 64)

                    fseek outputStream (recordOffset + 12) #seek_set
                    writeshort outputStream (parentBoneIndex - 1)
                    fseek outputStream (recordOffset + translationOffset) #seek_set
                    writefloat outputStream (localPosition.x / 100)
                    writefloat outputStream (localPosition.y / 100)
                    writefloat outputStream (localPosition.z / 100)
                    changedCount += 1
                )
                else
                (
                    appendIfUnique skippedNames subBoneName
                )
            )
        )

        if changedCount < 1 do
            throw "None of the selected scene bones could be matched to the source fbxskel."

        REEngineFBXSkelCloseStream outputStream
        outputStream = undefined

        if not (REEngineFBXSkelCommitTemp tempPath outputPath) do
            throw "The pose-preserving file could not replace the output path. Any previous output was preserved."
        tempPath = undefined

        #(outputPath, changedCount, skippedNames)
    )
    catch
    (
        REEngineFBXSkelCloseStream sourceStream
        REEngineFBXSkelCloseStream outputStream
        if tempPath != undefined and doesFileExist tempPath do
            try (deleteFile tempPath) catch ()
        throw()
    )
)

fn compareFN v1 v2 valArray: = (
	case of (
		(valArray[v1]  > valArray[v2] ):  1
		(valArray[v1]  < valArray[v2] ):  -1
		default: 0
	)
)

fn generate_hash key isWString seed:0xFFFFFFFFL = --generates a murmur3 hash from a string
(
	fn fmix h  seed:0xFFFFFFFFL =  --RE Engine seed is always 0xFFFFFFFF or 4294967295
	(
		h = bit.xor h (bit.shift h -16)
		h = bit.and (h * 0x85ebca6bL) seed
		h = bit.xor h (bit.shift h -13)
		h = bit.and (h * 0xc2b2ae35L) seed
		h = bit.xor h (bit.shift h -16)
		h
	)	
	local newKey = #(); 
	for i = 1 to key.count do ( 
		append newKey ((bit.charAsInt key[i]) as integer64)
		if isWString != 0 then append newKey 0L 
	)
	key = newKey
	local length = key.count as integer64
	local nBlocks = (length / 4) as integer64
	local h1 = seed 
	local c1 = 0xcc9e2d51L
	local c2 = 0x1b873593L		
	for block_start = 1 to (nblocks * 4) by 4 do ( 
		k1 = bit.or (bit.or (bit.or (bit.shift key[block_start + 3] 24) (bit.shift key[block_start + 2] 16)) (bit.shift key[block_start + 1] 8)) (key[block_start + 0])
		k1 = bit.and (c1 * k1) seed
		k1 = bit.and (bit.or (bit.shift k1 15) (bit.shift k1 -17)) seed
		k1 = bit.and (c2 * k1) seed
		h1 = bit.xor h1 k1
		h1 = bit.and (bit.or (bit.shift h1 13) (bit.shift h1 -19)) seed
		h1 = bit.and (h1 * 5 + 0xe6546b64L) seed
	)	
	local tail_index = (nblocks * 4) + 1; k1 = 0
	local tail_size = bit.and length 3
	if tail_size >= 3 then k1 = bit.xor k1 (bit.shift key[tail_index + 2] 16)
	if tail_size >= 2 then k1 = bit.xor k1 (bit.shift key[tail_index + 1] 8)
	if tail_size >= 1 then k1 = bit.xor k1 (key[tail_index + 0])
	if tail_size > 0 then (
		k1 = bit.and (k1 * c1) seed
		k1 = bit.and (bit.or (bit.shift k1 15) (bit.shift k1 -17)) seed
		k1 = bit.and (k1 * c2) seed
		h1 = bit.xor h1 k1
	)
	local unsigned_val = fmix (bit.xor h1 length)
	if (bit.and unsigned_val 0x80000000L) == 0 then 
		return unsigned_val
	else
		return -((bit.xor unsigned_val seed) + 1)
)

fn padToNextLine bstream = (
	while mod (ftell bstream) 16 != 0 do
		writebyte bstream 0
)

rollout REEngineFBXSkel "fbxskel Tool v0.1 + v0.4 - Max 2026" 
(
	group "Mode" (
		radiobuttons rb_Mode "" labels:#("v0.1 - Preserve current pose", "v0.4 - Official pose / full rebuild") default:2 columns:1
		label lblModeHint "The selected mode applies to both Import and Export." align:#center width:320
	)
	group "Import" (
		button ImportButton "Import fbxskel" tooltip:"Import a fbxskel skeleton using the selected mode"
	)
	group "Export" (
		button ExportButton "Export fbxskel" tooltip:"Writes a fbxskel file using the selected mode"
		checkbox chk_MeshAsSource "Mesh as Source" tooltip:"Export bones from a mesh skeleton (may have numbers)"
	)
	--group "Config" (
	--	checkbox chk_IsSF6 "SF6" tooltip:"Street Fighter 6 fbxskel.5"
	--)
	
	hyperlink lbl6 "By alphaZomega" address: "https://residentevilmodding.boards.net/thread/13450/fbxskel-tool-maxscript" align:#right --offset:[0, -20]

	on rb_Mode changed state do
	(
		chk_MeshAsSource.enabled = (state == 2)
		if state == 1 then
		(
			ImportButton.tooltip = "Import positions only and preserve the current character pose"
			ExportButton.tooltip = "Patch an existing fbxskel and preserve its rotations and scales"
		)
		else
		(
			ImportButton.tooltip = "Import full transforms and restore the official pose"
			ExportButton.tooltip = "Rebuild a complete fbxskel file from the selected scene bones"
		)
	)

	on REEngineFBXSkel open do
	(
		chk_MeshAsSource.enabled = (rb_Mode.state == 2)
	)
	
	on ImportButton pressed do (
		local filen = GetOpenFileName caption:"Select fbxskel file" typeRs:"fbxskel (*.fbxskel.2;*.fbxskel.3;*.fbxskel.5;*.NewSkel)|*.fbxskel.2;*.fbxskel.3;*.fbxskel.5;*.NewSkel|All files (*.*)|*.*|"
		if filen == undefined then
		(
			format " Abort\n"
		)
		else
		(
			local f = undefined
			try
			(
				f = fopen filen "rb"
				if f == undefined do throw "The selected file could not be opened."
				local version = ReadUInt f
				if (ReadUInt64 f) != 1852599155 do throw "Select a valid fbxskel file."
				if not (REEngineFBXSkelVersionSupported version) do throw ("Unsupported fbxskel version: " + (version as string))
				fseek f 0x10 #seek_set
				local bonesStartOffs = ReadUInt64 f
				fskip f 8
				local boneCount = ReadUInt64 f
				if boneCount < 1 do throw "The selected fbxskel file contains no bones."

				local namesOffs = #()
				local hierarchy = #()
				local indices = #()
				local bonesList = #()
				local posePreserveMode = (rb_Mode.state == 1)
				fseek f bonesStartOffs #seek_set
				for i = 1 to boneCount do
				(
					append namesOffs (ReadUInt64 f)
					fskip f 4
					append hierarchy ((ReadSShort f) + 1)
					append indices ((ReadSShort f) + 1)
					local rot
					local trans
					local scale
					if version == 5 then
					(
						rot = [readfloat f, readfloat f, readfloat f, readfloat f]
						trans = [readfloat f, readfloat f, readfloat f]
						readfloat f
						scale = [readfloat f, readfloat f, 1.0]
						fskip f 8
					)
					else
					(
						trans = [readfloat f, readfloat f, readfloat f]
						fskip f 4
						rot = [readfloat f, readfloat f, readfloat f, readfloat f]
						scale = [readfloat f, readfloat f, readfloat f]
						fskip f 4
					)
					local bone = dummy boxsize:[.1,.1,.1] showLinks:true showLinksOnly:false wirecolor:yellow
					if posePreserveMode then
					(
						-- v0.1 deliberately imports joint positions only. The source
						-- file's rotations remain ignored so the scene pose is preserved.
						bone.pos = [trans.x, trans.y, trans.z] * 100
					)
					else
					(
						bone.rotation = quat rot.x -rot.z rot.y rot.w
						bone.pos = [trans.x, -trans.z, trans.y] * 100
					)
					bone.scale = scale
					bonesList[i] = bone
				)

				for i = 1 to boneCount do
				(
					fseek f namesOffs[i] #seek_set
					bonesList[i].name = ReadWString f
				)

				for i = 1 to boneCount do
				(
					if hierarchy[i] != 0 do
					(
						bonesList[i].parent = bonesList[hierarchy[i]]
						local newTransform = bonesList[i].transform * bonesList[i].parent.transform
						if posePreserveMode then
							bonesList[i].pos = newTransform.row4
						else
							bonesList[i].transform = newTransform
					)
				)
				if posePreserveMode and bonesList.count > 0 do
					bonesList[1].transform = (matrix3 [1,0,0] [0,0,1] [0,-1,0] [0,0,0])
			)
			catch
			(
				messageBox ("fbxskel import failed.\n\n" + (getCurrentException() as string)) title:"fbxskel Tool v0.1 + v0.4 - Max 2026"
			)
			REEngineFBXSkelCloseStream f
		)
	)
	
	on ExportButton pressed do
	(
		if rb_Mode.state == 1 then
		(
			local poseSelection = selection as array
			local poseBones = REEngineFBXSkelCollectBoneTrees poseSelection

			if poseBones.count == 0 then
			(
				messageBox "Select at least one helper or bone before exporting." title:"fbxskel Tool v0.1 + v0.4 - Max 2026"
			)
			else
			(
				local sourceFile = GetOpenFileName caption:"Select the original fbxskel to preserve" typeRs:"fbxskel (*.fbxskel.2;*.fbxskel.3;*.fbxskel.5;*.NewSkel)|*.fbxskel.2;*.fbxskel.3;*.fbxskel.5;*.NewSkel|All files (*.*)|*.*|"
				if sourceFile != undefined do
				(
					try
					(
						local poseResult = REEngineFBXSkelExportPosePreserve sourceFile poseBones
						local successText = "Pose-preserving fbxskel saved.\n\nUpdated bones: " + (poseResult[2] as string)
						if poseResult[3].count > 0 do
							successText += "\nUnmatched scene bones skipped: " + (poseResult[3].count as string)
						successText += "\n\n" + poseResult[1]
						messageBox successText title:"fbxskel Tool v0.1 + v0.4 - Max 2026"
					)
					catch
					(
						messageBox ("Pose-preserving export failed.\n\n" + (getCurrentException() as string)) title:"fbxskel Tool v0.1 + v0.4 - Max 2026"
					)
				)
			)
			gc()
		)
		else
		(
		local bones = #()
		local selectedNodes = selection as array
		local newfileName = undefined
		local tempFileName = undefined
		local nf = undefined
		local exportSucceeded = false
		local errorMessage = ""

		for selectedNode in selectedNodes do
		(
			local selectedSuperClass = superclassof selectedNode
			if selectedSuperClass == helper or selectedSuperClass == BoneGeometry do
				append bones selectedNode
		)

		if bones.count == 0 then
		(
			messageBox "Select at least one helper or bone before exporting." title:"fbxskel Tool v0.1 + v0.4 - Max 2026"
		)
		else
		(
			newfileName = getSaveFileName caption:"Save fbxskel file (.2, .3 or .5)" types:"fbxskel (*.fbxskel.2;*.fbxskel.3;*.fbxskel.5)|*.fbxskel.2;*.fbxskel.3;*.fbxskel.5|All files (*.*)|*.*|"

			if newfileName != undefined do
			(
				local fileType = toLower (getFilenameType newfileName)
				local version = case fileType of
				(
					".2": 2
					".3": 3
					".5": 5
					default: 0
				)

				if not (REEngineFBXSkelVersionSupported version) then
				(
					messageBox "The output filename must end in .2, .3 or .5 (for example: skeleton.fbxskel.3)." title:"fbxskel Tool v0.1 + v0.4 - Max 2026"
				)
				else
				(
					tempFileName = newfileName + ".tmp." + ((timestamp()) as string)

					try
					(
						if doesFileExist tempFileName do deleteFile tempFileName
						if doesFileExist tempFileName do throw "A previous temporary file could not be removed."

						nf = fopen tempFileName "wb"
						if nf == undefined do throw "The output file could not be opened for writing."

						-- Header
						writelong nf version
						writelong nf 1852599155
						writelonglong nf 0
						writelonglong nf 48
						writelonglong nf 0
						writelonglong nf bones.count
						writelonglong nf 0

						-- Resolve every output name and parent before writing any bone.
						-- This makes hierarchy IDs independent of selection order.
						local namesArr = #()
						local rawNamesArr = for boneNode in bones collect boneNode.name
						local parentIndices = #()
						for i = 1 to bones.count do
						(
							append namesArr (REEngineFBXSkelNameOnly rawNamesArr[i])
							local parentIndex = 0
							if bones[i].parent != undefined do
								parentIndex = findItem rawNamesArr bones[i].parent.name
							append parentIndices parentIndex
						)

						-- Bones
						for i = 1 to bones.count do
						(
							local SubBoneID = i - 1
							local ParentBoneID = parentIndices[i] - 1
							local SubBoneName = namesArr[i]
							local BoneLocalMat = copy bones[i].transform

							if chk_MeshAsSource.state do
							(
								local tempRow = BoneLocalMat.row2
								BoneLocalMat.row2 = BoneLocalMat.row3 * -1
								BoneLocalMat.row3 = tempRow
							)

							-- A parent outside the exported selection is intentionally treated
							-- as a root, so no dangling parent ID is written.
							if parentIndices[i] > 0 do
							(
								local pMat = copy bones[parentIndices[i]].transform
								if chk_MeshAsSource.state do
								(
									local tempParentRow = pMat.row2
									pMat.row2 = pMat.row3 * -1
									pMat.row3 = tempParentRow
								)
								BoneLocalMat *= (inverse pMat)
							)

							writelonglong nf 0
							writelong nf (generate_hash SubBoneName 1)
							writeshort nf ParentBoneID

							local symmetryID = SubBoneID
							if findString SubBoneName "eapon" != undefined do symmetryID = -1
							local prefix = if SubBoneName.count >= 2 then substring SubBoneName 1 2 else ""
							local oppositePrefix = undefined
							if prefix == "R_" then oppositePrefix = "L_"
							else if prefix == "r_" then oppositePrefix = "l_"
							else if prefix == "L_" then oppositePrefix = "R_"
							else if prefix == "l_" then oppositePrefix = "r_"
							if oppositePrefix != undefined do
							(
								local oppositeBoneName = replace SubBoneName 1 2 oppositePrefix
								for j = 1 to namesArr.count do
								(
									if namesArr[j] == oppositeBoneName do
									(
										format "Symmetry bone '%' found for bone '%'\n" bones[j].name bones[i].name
										symmetryID = j - 1
										exit
									)
								)
							)
							writeshort nf symmetryID

							if version == 5 then
							(
								writefloat nf (-BoneLocalMat.rotation.x)
								writefloat nf (-BoneLocalMat.rotation.z)
								writefloat nf (BoneLocalMat.rotation.y)
								writefloat nf (BoneLocalMat.rotation.w)
								writefloat nf (BoneLocalMat.row4.x / 100)
								writefloat nf (BoneLocalMat.row4.z / 100)
								writefloat nf (-BoneLocalMat.row4.y / 100)
								writefloat nf 1
							)
							else
							(
								writefloat nf (BoneLocalMat.row4.x / 100)
								writefloat nf (BoneLocalMat.row4.z / 100)
								writefloat nf (-BoneLocalMat.row4.y / 100)
								writefloat nf 0
								writefloat nf (-BoneLocalMat.rotation.x)
								writefloat nf (-BoneLocalMat.rotation.z)
								writefloat nf (BoneLocalMat.rotation.y)
								writefloat nf (BoneLocalMat.rotation.w)
							)

							writefloat nf (BoneLocalMat.scale.x)
							writefloat nf (BoneLocalMat.scale.y)
							if version == 5 then writefloat nf 0 else writefloat nf (BoneLocalMat.scale.z)
							writefloat nf 0
						)

						padToNextLine nf

						local hashesOffset = ftell nf
						local indexArr = for i = 1 to bones.count collect i
						local hashArr = #()
						for i = 1 to namesArr.count do
						(
							local hash = (generate_hash namesArr[i] 1) as integer
							if hash < 0 do hash = 1L + 0xFFFFFFFFL + (hash as integer64)
							append hashArr (hash as integer64)
						)

						qsort indexArr compareFN valArray:hashArr
						for i = 1 to indexArr.count do
						(
							writelong nf (hashArr[indexArr[i]] as integer)
							writelong nf (indexArr[i] - 1)
						)

						padToNextLine nf

						local strOffsArr = #()
						for i = 1 to namesArr.count do
						(
							append strOffsArr (ftell nf)
							writeUnicodeString nf namesArr[i]
						)

						fseek nf 48 #seek_set
						for i = 1 to strOffsArr.count do
						(
							writelonglong nf strOffsArr[i]
							fseek nf 56 #seek_cur
						)
						fseek nf 24 #seek_set
						writelonglong nf hashesOffset

						REEngineFBXSkelCloseStream nf
						nf = undefined

						if not (REEngineFBXSkelCommitTemp tempFileName newfileName) do
							throw "The completed file could not replace the selected output path. The original target was preserved."

						tempFileName = undefined
						exportSucceeded = true
					)
					catch
					(
						errorMessage = getCurrentException() as string
					)

					REEngineFBXSkelCloseStream nf
					if tempFileName != undefined and doesFileExist tempFileName do
						try (deleteFile tempFileName) catch ()

					if exportSucceeded then
						messageBox ("New fbxskel file saved.\n\n" + newfileName) title:"fbxskel Tool v0.1 + v0.4 - Max 2026"
					else
						messageBox ("fbxskel export failed.\n\n" + errorMessage) title:"fbxskel Tool v0.1 + v0.4 - Max 2026"
				)
			)
		)

		gc()
		)
	)
)

try (destroyDialog REEngineFBXSkel) catch ()
clearlistener
createDialog REEngineFBXSkel 350 240

)
