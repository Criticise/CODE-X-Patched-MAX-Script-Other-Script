--RER mod tool v0.2 by maliwei777
--Edited By mariokart64n June 11, 2013 -> Added version switch for RER and Re6
--v0.21 - Edited by Sectus. Fixed material ID (was a byte, but should be a short)
--May 7, 2014. RE5 mod tool 0.1.  ported to support RE5 character mod file by aman. 
--		Export mesh to triangle list. Run RE5TriStrip to convert export .NewMod to RE5 compatible mod file.
--  RE5 Mod tool 0.2  - by aman -- fixed a bone map export bug that crashes script when processing a mesh that have more than 4 bones assigned to a vertex. 
-- v0.21 - by aman - remove degenerated triangles which mess up Skin Wrap modifier on control point assignment
-- v0.23 - by aman -fixed export invalid uv crashes
-- v0.25 - by aman -fixed import mesh vertical postion (z-direction) bug
-- v0.26 - by aman -convert material type 0x89 to 0x81 to support 4 bones vertex, convert all 8 bones vertices to 4 bones format. this fix export bug for chris warrior and sheva business
-- v0.27  - May 16,2014 -aman- add cut-scene head supports
-- v0.29  - Feb 26, 2015 -aman = Fix FShort (= as ==) comparison bug. Add support for loading PS3-converted gold edition characters and mod tools exported characters
-- v0.31  - Apr 28, 2015 -aman , change ':' to 'x' in mesh name. Add simple stage mod import/export. Only supports vertex positions editing for existing stage mesh 
-- v0.31a  - May 9, 2015 -aman , create visible boundary data for stage meshes (experimental) to prevent edit mesh disappear at some camera angle. 
            --  handle vertex index 16 bit overflow (by increase index base in mesh header). fixed messed up face of last mesh in mod(required new RE5TriStrip v0.2 to work )
-- v0.31c  June, 6 2015 -aman, support stage vertex type 0x04, fix rename select. fix bone model vertex type 0x08 export.
-- v0.31d  June, 9 2015 -aman, support import of bones mesh vertex type 0x04. fixed em1000 em1100.mod import error.
-- v0.31e  June, 16 2015 -aman, fix mod boundary calculation
-- v0.33a   Oct, 26 2020 -aman, fix crash casue by modding Chris cutscene head. fix 3dsmax not deforming single bone vertex issue.
--
-- **********************************************************************
-- RE5 Codex Maintenance / DEBUG Notes 2026-06-30
-- **********************************************************************
-- [Scope of current Codex maintenance lane]
-- 1. Keep RE5 import/export format logic intact.
-- 2. Focus on Max 2026/2027 compatibility, UI responsiveness, progress feedback,
--    bilingual UI text, and low-risk export-side speed gains.
-- 3. Do not pull this file toward V4-scale modularization yet. This script is
--    still a lightweight single-rollout maintenance target.
--
-- [Compatibility rules]
-- 1. FShort currently uses the pure MAXScript path, not old XNA.
--    Do not restore XNA as a hard dependency for Max 2026/2027 support.
-- 2. New compatibility code should wrap UI refresh / message pumping / version
--    detection only. Avoid touching RE5 binary field math unless the file format
--    itself is proven broken.
--
-- [Performance rules]
-- 1. Prefer per-mesh cache over full-scene cache.
-- 2. Safe target: cache selected mesh verts / tverts / faces once per mesh, then
--    reuse in later export passes.
-- 3. Do not re-introduce giant whole-export caches or whole-file staging.
-- 4. Progress updates must be sparse. Updating UI every vertex is slower.
-- 5. For import-side speed, first suspect Max scene creation / SkinOps / redraw.
--    Do not assume binary file reading is the bottleneck unless measured.
-- 6. V4-style "looks like final result appears directly" is mostly about scene/UI
--    batching, not magic file parsing speed.
-- 7. Current 2026/2027 export optimization lane is intentionally narrow:
--    a. unchanged character mesh vertex fast-copy
--    b. Skin LUT + Top4 cache
--    c. lower-cost Edit Normals cache path with legacy fallback
--    d. face writer cache reuse
--    e. export format() logs behind a debug switch
--    These are speed experiments, not format changes.
--
-- [Export experimental toggles - 2026-06-30]
-- 1. Globals near the top of this file control this lane:
--    RE5ExportExperimentalOptimizations
--    RE5ExportFastCopyUnchangedCharacterMeshes
--    RE5ExportUseTop4SkinCache
--    RE5ExportOptimizeNormalCache
--    RE5ExportReuseCachedFaceArrays
--    RE5ExportVerboseDebug
-- 2. Master off should drop export back to the legacy hot path wherever possible.
-- 3. If a regression points at normals first, disable RE5ExportOptimizeNormalCache
--    before touching any other switch.
-- 4. Fast-copy only applies to unchanged character meshes when BoundChange == false
--    and no 0x08 -> 4-bone conversion is required.
-- 5. Skin cache optimization must keep bone naming semantics compatible with the
--    legacy export path. No bone remap logic should be changed silently.
-- 6. Added a modular header-only export shortcut lane for mesh-name-field overrides.
--    Current default use case: selected mesh changes only LOD-related name intent.
--    In that case export keeps original .mod geometry and only rewrites the mesh
--    header field mapped from the imported Mesh_* naming convention, then skips all
--    scene geometry work for that mesh.
-- 7. This lane is intentionally modular and attached beside the export flow, not
--    buried inside vertex/face write rules, so future header-only cases can be
--    expanded without contaminating hot loops.
--
-- [Header-only export shortcut - 2026-06-30]
-- 1. Globals near the top of this file control this lane:
--    RE5ExportEnableHeaderOnlyNameOverrides
--    RE5ExportHeaderOnlyAllowLOD
--    RE5ExportHeaderOnlyAllowMatId
--    RE5ExportHeaderOnlyAllowGroup
--    RE5ExportHeaderOnlyAllowDisplayMode
-- 2. Current default is LOD-only enabled. MatID / Group / DisplayMode are left
--    off until their RE5 header mapping is proven and explicitly enabled.
-- 3. Header-only path means:
--    a. keep original mesh geometry from source .mod
--    b. do not read scene verts/faces/uv/weights for that mesh
--    c. rewrite allowed header field(s) only
-- 4. If future rename-only requests expand to MatID / Group / DisplayMode, extend
--    this same module rather than duplicating logic elsewhere.
-- 5. Code-level globals are the only debug switches for this module. Do not
--    expose a user-facing UI toggle for header-only export, because turning it
--    off would silently roll users back to the slower legacy path.
-- 6. Follow-up wiring in this pass also routes future Group / DisplayMode target
--    values through the same header-only write lane, but leaves their switches
--    off by default. Turning those on later should not require touching the
--    vertex/face hot path again.
-- 7. Safety rule: header-only must never trigger from name fields alone. It now
--    requires a scene-vs-source unchanged mesh check first; if unchanged status
--    cannot be proven, export must fall back to the normal modified-mesh path.
-- 8. Follow-up lane for 2026/2027: export now prefers a manual per-mesh action
--    dialog before writing .NewMOD:
--    a. MOD MESH
--    b. NAME-FIELD ONLY
--    c. DELETE
--    Automatic header-only detection is kept in code for rollback/debug, but is
--    disabled by default at code level.
-- 9. Current code-level default:
--    RE5ExportEnableAutoHeaderOnlyDetection = false
--    Manual dialog path is the active lane. Do not delete the auto path; keep it
--    dormant so future rollback/testing can re-enable it quickly.
-- 10. Manual dialog UI is now a three-lane export splitter:
--     top    = NAME-FIELD ONLY (current safe UI mode: LOD=0 / MAT_ID / DISPLAYMODE)
--     middle = DELETE
--     bottom = MOD MESH
--     The dialog now opens empty. Selected scene Mesh_* nodes must be loaded into
--     a lane explicitly by that lane's own read button before export starts.
-- 11. Current DELETE behavior is export-safe suppression, not physical mesh-table
--     removal: the mesh slot stays in MeshCount, but its written vert/face counts
--     become zero so geometry is omitted without destabilizing RE5 mesh offsets.
-- 12. Manual export dialog keeps one candidate row per mesh index and one action
--     id per row, so the same mesh should never exist in all three lanes during
--     normal use. Keep a final OK-time duplicate warning anyway as a low-risk
--     guard against future UI/state corruption.
-- 13. This dialog must stay non-modal. Users need to keep the export splitter
--     open while changing scene selection, then click the reload button to pull
--     the latest Mesh_* selection into the bottom lane.
-- 14. 2026-07-01 wording/behavior verification for the top lane:
--     a. UI wording must describe Mesh_* name-mapped fields, not generic "Force LOD 0".
--     b. Write lane confirmed at mesh-table export:
--        headerOnlyOverride[6] -> MatId
--        headerOnlyOverride[7] -> bonemapindex (imported UI label GROUPID)
--        headerOnlyOverride[8] -> lodLevel
--        headerOnlyOverride[9] -> unk07 (imported UI label DISPLAYMODE)
--     c. That lane keeps original vert/face counts, starts, bases, weights, UVs,
--        and source geometry. It only rewrites the mapped mesh header fields above.
--     d. Manual LOD=0 mode is intentionally constant-write lodLevel=0. It is not a
--        generic "copy scene name LOD value" mode.
--     e. Historical mapping notes above are kept for debug/reference. Current
--        RE5 manual UI exposes the safe LOD=0 / MAT_ID / DISPLAYMODE variants,
--        while GROUPID stays disabled.
-- 15. 2026-07-01 manual export splitter UI behavior fix:
--     a. Root causes from user feedback:
--        - top hint label had fixed height, so long bilingual text overlapped controls
--        - "Read Current Selection" rebuilt candidates with default action=MOD MESH,
--          so newly loaded Mesh_* always fell into the bottom lane
--        - clear button on modified lane only cleared visible selection bits and did
--          not mutate candidate data, so the lane appeared unchanged
--     b. Current method:
--        - dialog now computes hint line count and reapplies lane/button Y positions
--          through RE5_ManualExportApplyLayout()
--        - load path now merges current scene selection into the active target lane
--          via RE5ManualExportLoadTargetActionId + RE5_ManualExportMergeLoadedItems()
--        - each lane now has Select All + Clear controls
--     c. Clear semantics:
--        - NAME-FIELD ONLY clear  -> revert those candidates to MOD MESH
--        - DELETE clear           -> revert those candidates to MOD MESH
--        - MOD MESH clear         -> remove those candidates from the dialog list
--     d. Workflow intent:
--        - move/select buttons also update the current load target lane
--        - user can keep the dialog open, choose the destination lane, select more
--          Mesh_* in scene, then click Read Current Selection to append/replace into
--          that chosen lane instead of always restarting at the bottom lane
-- 16. 2026-07-01 manual export splitter close behavior fix:
--     a. Closing the three-lane dialog with window X must abort export.
--     b. Visible SKIP fallback is now disabled by default; close/X is the normal
--        abort path for this dialog.
--     c. Export entry now treats dialog result #cancel as a hard stop, closes
--        file handles, deletes the half-written .NewMOD stub, and returns.
-- 17. 2026-07-01 manual export target-lane selection fix:
--     a. User feedback showed "Read Current Selection" still defaulted to the
--        bottom MOD MESH lane unless a move/select/clear button had been used first.
--     b. Root cause: target lane state only changed through buttons; clicking a
--        lane list itself never updated RE5ManualExportLoadTargetActionId.
--     c. Current fix:
--        - clicking any lane list row now sets that lane as the read target
--        - lane titles show the current read target explicitly
--        - dialog hint now explains the top header-only lane is faster because it
--          rewrites mesh header fields only and skips traditional geometry export
-- 18. 2026-07-01 manual export read-per-lane rewrite:
--     a. Follow-up user feedback: the shared bottom "Read Current Selection"
--        control kept the workflow ambiguous.
--     b. New rule:
--        - the dialog opens with all three lanes empty
--        - each lane has its own "Read Current Selection" button
--        - pressing a lane-local read button merges current scene Mesh_* into
--          that exact lane and reassigns existing rows if needed
--        - no auto-fill into MOD MESH on dialog open
-- 19. 2026-07-01 manual export candidate-authority fix:
--     a. The three export lanes must be the authoritative source for manual export.
--     b. Once the dialog returns OK, normal modified-mesh export must only use
--        meshes that were explicitly loaded into those lanes.
--     c. Empty-lane OK is now blocked; the user must load at least one Mesh_*
--        into a lane or close the dialog to abort.
-- 20. 2026-07-01 manual export performance isolation fix:
--     a. Only the bottom MOD MESH lane is allowed to enter the legacy modified-
--        mesh export path and its heavy scene-cache / geometry analysis work.
--     b. Header-only lane now supplies header field values only.
--     c. Delete lane now supplies delete flags only.
--     d. If export still feels slow with only lane 1 / lane 2 populated, recheck
--        for accidental cache work outside the MOD MESH selection set first.
-- 21. 2026-07-01 RE5 header-only skin safety restriction:
--     a. User feedback confirmed some lane-1 exports appeared to "lose Skin".
--     b. Root cause: the imported UI label GROUPID maps to RE5 mesh header
--        bonemapindex. For character meshes this is bone-map linkage, not a
--        harmless display-only field.
--     c. Manual lane-1 export is now clamped to the safe LOD=0 header-only path.
--        It keeps source geometry / weights / UVs and only rewrites lodLevel=0.
--     d. MAT_ID / GROUPID / DISPLAYMODE header-only ideas stay in code history for
--        future investigation, but are no longer exposed through the current UI.
-- 22. 2026-07-01 RE5 header-only safe reopen:
--     a. MAT_ID and DISPLAYMODE are now reopened for the manual header-only lane.
--     b. GROUPID stays disabled because it maps to bonemapindex and can break Skin.
--     c. Header-only pre-pass now uses an early lightweight mesh-header reader
--        instead of depending on later full reader binding at runtime. This is to
--        avoid the Max-side "Call needs function or class, got: undefined" failure
-- 23. 2026-07-01 RE5 import empty-slot safety fix:
--     a. Manual DELETE keeps the original mesh slot in the .mod mesh table but
--        writes vertCount/faceCount = 0 for that slot.
--     b. Import previously still tried to build an Editable_Mesh, set TVerts,
--        and run buildTVFaces on those zero-geometry slots.
--     c. Real symptom seen by user: import could stop early on a deleted slot
--        (example crash around Mesh_094...) with "buildTVFaces: mesh has no
--        texture vertices", which then made later valid meshes such as LOD255
--        mesh 184 appear "missing".
--     d. Current fix: import now treats zero vert / zero face / missing UV data
--        as an intentionally empty slot, skips scene mesh creation for that slot,
--        leaves ImportedMeshNodes[i] = undefined, and continues importing later
--        mesh indices unchanged.
--     e. This is an import safety fix only. It does not renumber mesh indices
--        and does not change the three-lane export routing rules.
--        seen in RE5_BuildManualHeaderOnlyOverrideFlags / RE5_FindHeaderOnlySelectionIndices.
-- 24. 2026-07-01 manual export guidance / no-skin guard:
--     a. RE6 modding experience text is now centralized in helper functions:
--        - RE5_BuildManualExportGuidanceRulesText()
--        - RE5_BuildManualExportQuickAdviceText()
--        Update those helpers first if future rule wording changes.
--     b. Export lane guide now auto-opens before the three-lane dialog, with a
--        persistent "do not auto-show again" setting stored in RE5_Codex_UI.ini.
--     c. If the user places a no-Skin mesh into lane 3 (traditional MOD MESH),
--        export must reactivate guidance even if auto-show had been disabled,
--        because this is a known unsafe routing case.
--     d. The lane-3 no-Skin guard must stay outside binary export code. It is a
--        UI/routing correction layer only.
--     e. Current correction options are:
--        - move the offending mesh set to lane 1
--        - move the offending mesh set to lane 2
--        - go back and inspect manually
--        Do not silently auto-reroute without telling the user.
-- 25. 2026-07-01 RE5 guide / no-Skin anti-misuse follow-up:
--     a. Guide text and no-Skin warning text now route through one center helper:
--        RE5_BuildExportGuideText mode detailText
-- 26. 2026-07-01 RE5 export splitter SKIP shutdown:
--     a. Visible SKIP fallback is disabled by code-level switch.
--     b. Reason: SKIP allowed users to bypass the new three-lane export routing
--        UI and fall back to the old/default export behavior.
--     c. Old #skip path is intentionally kept in code for rollback/debug only,
--        but normal UI must use the new lanes or abort.
-- 26b. 2026-07-01 RE5 guide SKIP semantic correction:
--      a. The guide dialog sits before the real three-lane export dialog, so its
--         SKIP must mean "skip guide text only", not "abort export".
--      b. Correct behavior:
--         - Guide OK   = continue into the three-lane dialog
--         - Guide SKIP = continue into the three-lane dialog
--         - Close/X    = abort export
--      c. Root cause: a previous Codex change rewired guide SKIP to #cancel,
--         which contradicted the button meaning and old RE5 behavior.
-- 26c. 2026-07-01 RE5 export-dialog bottom-button layout rule:
--      a. The single visible OK button uses window horizontal center as the
--         alignment reference; its vertical row stays unchanged.
--      b. The guide dialog follows the same rule when its own SKIP button is
--         hidden.
--      c. If RE5ExportEnableManualMeshActionSkip is enabled again later, both the
--         guide dialog and the three-lane export dialog already fall back to the
--         original two-button layout through the existing skipEnabled branch.
--     b. The lane-3 no-Skin warning now includes both parent hierarchy and
--        direct children for each offending Mesh_* node, so scene context is
--        visible before the user decides lane 1 / lane 2 / back.
--     c. The general guide dialog and no-Skin warning dialog now use multiline
--        auto-wrap + auto-height text controls instead of fixed-height edittext.
--     d. The export guide auto-show path remains attached to ExportToMod and
--        keeps the persistent "do not auto-show again" toggle in RE5_Codex_UI.ini.
--     e. If lane 3 hits the no-Skin guard, AutoShowGuide is re-enabled again so
--        the user can re-see the ordinary export guide on later exports.
--     f. The first lane naming stays unchanged in this pass by design. Only the
--        guidance plumbing and anti-misuse dialogs were consolidated.
-- 26. 2026-07-01 RE5 warning-flow correction after V4 comparison:
--     a. "reactivate the ordinary export guide" means restoring the guide state,
--        not spawning that ordinary guide immediately during the lane-1 / lane-2
--        move button click from the no-Skin warning.
--     b. Correct lane-3 no-Skin move behavior:
--        1. reroute the offending mesh set to lane 1 or lane 2
--        2. keep RE5ManualExportGuideAutoShow = true
--        3. persist that state through RE5_SaveManualExportGuideSettings()
--        4. return to the three-lane dialog without an extra ordinary guide popup
--     c. A previous Codex attempt added an immediate
--        RE5_ShowManualExportGuideDialog forceShow:true call after the move
--        buttons. That was UI overreach, not requested behavior, and is now
--        explicitly removed.
--     d. Practical rule for future AI changes on this lane:
--        if the user asks to "reactivate" or "re-enable" a warning/guide, do not
--        assume they also asked to "show it immediately". Restore state first;
--        add a new popup only if they explicitly request that extra step.
-- 27. 2026-07-01 RE5 guide / no-Skin visual polish pass:
--     a. The two warning dialogs now share the same dark read-only text panel
--        style instead of the old white textbox block.
--     b. Text selection highlight is cleared after assigning content so the
--        dialog no longer opens with blue selected text.
--     c. Content width, inner padding, and auto-height ranges were tuned for
--        denser Chinese text so wrapping looks less cramped.
--     d. Guide copy was repartitioned into short titled sections. Keep future
--        wording changes in the helper builders instead of hardcoding UI lines.
--
-- [RE5 .NewMOD reimport face fix - 2026-06-30]
-- 1. Character/stage meshes modified by this exporter are written as triangle-list
--    inside .NewMOD and flagged with mesh vertFlag bit 0x80 until RE5TriStrip runs.
-- 2. Legacy import always decoded mesh faces as strip data, which makes exported
--    .NewMOD files reimport into Max as exploded / collapsed spike meshes.
-- 3. Import must detect bit 0x80 and read that mesh face section as explicit
--    3-index triangles instead of strip expansion.
-- 4. This is an import-preview compatibility fix only. Final game-facing .mod
--    still comes from the external RE5TriStrip conversion step.
--
-- [Import speed / visual behavior findings - 2026-06-30]
-- 1. RE5 import was visually exposing intermediate state because UI pumping stayed
--    active while meshes were being created and before deferred skin finished.
-- 2. Matching V4 means:
--    a. build all mesh nodes first
--    b. defer Skin application to a second pass
--    c. wrap the whole import in batch scene ops
--    d. suppress windows.processPostedMessages() while batch import is active
-- 3. This maintenance pass wires that behavior into:
--    a. RE5_BeginImportBatchOp / RE5_EndImportBatchOp
--    b. RE5_ProcessUI gate via RE5ImportBatchActive
--    c. on ImportButton pressed do
--    d. RE5_ApplyDeferredImportSkin second-pass usage
-- 4. Import failure handling was also tightened:
--    a. invalid non-MOD files now abort immediately
--    b. file handles close on both success and failure
--    c. batch scene state is restored before returning
-- 5. If future import tuning is needed, prioritize:
--    a. mesh build loops
--    b. setTVert / setTVFace cost
--    c. SkinOps cost
--    Do not jump back to whole-file memory staging without proof.
--
-- [UI / language rules]
-- 1. Keep language layer simple: ZH_CN / EN only.
--    First-open language may follow environment detection, but once the user
--    switches EN / ZH_CN manually, that manual choice must win for the rest of
--    the session. Do not "fix" this by removing the switch behavior.
-- 2. Keep progress UI lightweight. One bar + one status line is enough.
-- 3. Do not build a complex layout/font system unless this script grows far
--    beyond its current size.
-- 4. UI layout should stay computed from content blocks. Do not go back to
--    fixed coordinates or separate hand-tuned EN/CN rect tables.
-- 5. Keep rollout layout logic isolated from import/export core logic. Text or
--    control reflow changes must not alter file format behavior.
--
-- [Rejected directions]
-- 1. No format rewrite.
-- 2. No split into multiple .ms files for now.
-- 3. No .NET / Python bridge for hot loops.
-- 4. No "modernization" that changes RE5 import/export behavior by accident.
-- **********************************************************************

global mod_ver = 0,Re5ModTool
global RE5RuntimeMaxMajor = 0
global RE5RuntimeUseBulkMeshReads = false
global RE5UILanguage = undefined
global RE5UIManualLanguageOverride = false
global RE5ProgressLastValue = -1
global RE5ProgressLastText = ""
global RE5ProgressLastTick = 0
global RE5ProgressThrottleMs = 90
global RE5ImportBatchActive = false
global RE5ExportExperimentalOptimizations = true
global RE5ExportFastCopyUnchangedCharacterMeshes = true
global RE5ExportUseTop4SkinCache = true
global RE5ExportOptimizeNormalCache = true
global RE5ExportReuseCachedFaceArrays = true
global RE5ExportVerboseDebug = false
global RE5ExportEnableHeaderOnlyNameOverrides = true
global RE5ExportEnableAutoHeaderOnlyDetection = false
global RE5ExportEnableManualMeshActionDialog = true
global RE5ExportEnableManualMeshActionSkip = false
global RE5ExportHeaderOnlyAllowLOD = true
global RE5ExportHeaderOnlyAllowMatId = true
global RE5ExportHeaderOnlyAllowGroup = false
global RE5ExportHeaderOnlyAllowDisplayMode = true
global RE5ExportHeaderOnlyRequireSceneMatch = true
global RE5ManualExportActionCandidates = #()
global RE5ManualExportActionResult = #skip
global RE5ManualExportActionMeshCount = 0
global RE5ManualExportHeaderOnlyMode = 1
global RE5ManualExportLoadTargetActionId = -1
global RE5SettingsIniPath = ""
global RE5ManualExportGuideAutoShow = true
global RE5ManualExportGuideSettingsLoaded = false
global RE5ManualExportGuideDialogResult = #cancel
global RE5ManualExportNoSkinDialogResult = #back
global RE5ManualExportNoSkinDialogItems = #()

fn paddstring len instring =
(
	instring = instring as string
	local str = ""
	if instring.count <= len then
	(
		for i = 1 to (len - instring.count) do
		(
			str += "0"
		)
		str = (str + instring)
	)
	else
	(
		for i = 1 to len do
		(
			str += "0"
			str[i] = instring[i]
		)
	)
	str
)

--XNA "Microsoft.Xna.Framework.dll" ·�� 
--dotnet.loadassembly @"C:\Program Files (x86)\Common Files\microsoft shared\XNA\DeployableRuntimes\Zune\3.1.10527.0\Microsoft.Xna.Framework.dll"
-- dotnet.loadassembly @"C:\Program Files (x86)\Common Files\microsoft shared\XNA\DeployableRuntimes\Zune\3.1.10527.0\Microsoft.Xna.Framework.dll"

fn RE5_GetMaxMajorVersion =
(
	local result = 0
	try
	(
		local maxVersionInfo = maxVersion()
		if maxVersionInfo != undefined do
		(
			if isKindOf maxVersionInfo Array then
			(
				if maxVersionInfo.count >= 1 do result = maxVersionInfo[1]
			)
			else
			(
				try (result = maxVersionInfo[1]) catch()
			)
		)
	)
	catch(result = 0)
	result
)

fn RE5_IsExportOptimizationEnabled optionFlag =
(
	(RE5ExportExperimentalOptimizations == true and optionFlag == true)
)

fn RE5_ShouldUseExportVerboseDebug =
(
	(RE5ExportVerboseDebug == true)
)

fn RE5_CopyBinaryRange sourceFile targetFile byteCount =
(
	local safeByteCount = 0
	local longCount = 0
	local remainCount = 0
	local tempLong = 0
	local tempByte = 0
	try (safeByteCount = byteCount as integer) catch(safeByteCount = 0)
	if safeByteCount <= 0 do return true
	longCount = floor (safeByteCount / 4.0)
	remainCount = safeByteCount - (longCount * 4)
	for copyIndex = 1 to longCount do
	(
		tempLong = ReadLong sourceFile #unsigned
		WriteLong targetFile tempLong
	)
	for copyIndex = 1 to remainCount do
	(
		tempByte = ReadByte sourceFile #unsigned
		WriteByte targetFile tempByte
	)
	true
)

fn RE5_ParseGameBoneIdFromBoneName boneName =
(
	local boneId = 1
	if boneName != undefined and boneName != "" do
	(
		try (boneId = execute ((filterString boneName "_")[3])) catch(boneId = 1)
	)
	boneId
)

fn RE5_GetSelectMeshHeaderField selectMeshHeaderInfo fieldIndex defaultValue =
(
	if selectMeshHeaderInfo != undefined and selectMeshHeaderInfo.count >= fieldIndex and selectMeshHeaderInfo[fieldIndex] != undefined then
		selectMeshHeaderInfo[fieldIndex]
	else
		defaultValue
)

struct RE5LiteMeshHeader
(
	meshtype,
	MatId,
	unk01,
	lodLevel,
	unk02,
	vertStride,
	vertFlag,
	unk04,
	vertCount,
	vertEnd,
	vertStart,
	vertBase,
	vertBase2,
	faceStart,
	faceCount,
	faceBase,
	unk06,
	unk07,
	vertStart2,
	weightmaps,
	bonemapindex,
	min_index,
	max_index,
	unk09
)

fn RE5_ReadMeshHeaderLite bstream =
(
	local M = RE5LiteMeshHeader()
	if bstream == undefined do return undefined
	M.meshtype = ReadShort bstream #unsigned
	M.MatId = ReadShort bstream #unsigned
	M.unk01 = ReadByte bstream #unsigned
	M.lodLevel = ReadByte bstream #unsigned
	M.unk02 = ReadShort bstream #unsigned
	M.vertStride = ReadByte bstream #unsigned
	M.vertFlag = ReadByte bstream #unsigned
	M.unk04 = ReadShort bstream #unsigned
	M.vertCount = ReadShort bstream #unsigned
	M.vertEnd = ReadShort bstream #unsigned
	M.vertStart = ReadLong bstream #unsigned
	M.vertBase = ReadLong bstream #unsigned
	M.vertBase2 = ReadLong bstream #unsigned
	M.faceStart = ReadLong bstream #unsigned
	M.faceCount = ReadLong bstream #unsigned
	M.faceBase = ReadLong bstream #unsigned
	M.unk06 = ReadByte bstream #unsigned
	M.unk07 = ReadByte bstream #unsigned
	M.vertStart2 = ReadShort bstream #unsigned
	M.weightmaps = ReadByte bstream #unsigned
	M.bonemapindex = ReadByte bstream #unsigned
	M.min_index = ReadByte bstream #unsigned
	M.max_index = ReadByte bstream #unsigned
	M.unk09 = ReadLong bstream #unsigned
	M
)

fn RE5_GetMeshHeaderLiteField meshHeaderLite fieldId defaultValue =
(
	if meshHeaderLite == undefined then
	(
		defaultValue
	)
	else
	(
		case fieldId of
		(
			#meshtype: (if meshHeaderLite.meshtype != undefined then meshHeaderLite.meshtype else defaultValue)
			#matid: (if meshHeaderLite.MatId != undefined then meshHeaderLite.MatId else defaultValue)
			#unk01: (if meshHeaderLite.unk01 != undefined then meshHeaderLite.unk01 else defaultValue)
			#lodLevel: (if meshHeaderLite.lodLevel != undefined then meshHeaderLite.lodLevel else defaultValue)
			#unk02: (if meshHeaderLite.unk02 != undefined then meshHeaderLite.unk02 else defaultValue)
			#vertStride: (if meshHeaderLite.vertStride != undefined then meshHeaderLite.vertStride else defaultValue)
			#vertFlag: (if meshHeaderLite.vertFlag != undefined then meshHeaderLite.vertFlag else defaultValue)
			#unk04: (if meshHeaderLite.unk04 != undefined then meshHeaderLite.unk04 else defaultValue)
			#vertCount: (if meshHeaderLite.vertCount != undefined then meshHeaderLite.vertCount else defaultValue)
			#vertEnd: (if meshHeaderLite.vertEnd != undefined then meshHeaderLite.vertEnd else defaultValue)
			#vertStart: (if meshHeaderLite.vertStart != undefined then meshHeaderLite.vertStart else defaultValue)
			#vertBase: (if meshHeaderLite.vertBase != undefined then meshHeaderLite.vertBase else defaultValue)
			#vertBase2: (if meshHeaderLite.vertBase2 != undefined then meshHeaderLite.vertBase2 else defaultValue)
			#faceStart: (if meshHeaderLite.faceStart != undefined then meshHeaderLite.faceStart else defaultValue)
			#faceCount: (if meshHeaderLite.faceCount != undefined then meshHeaderLite.faceCount else defaultValue)
			#faceBase: (if meshHeaderLite.faceBase != undefined then meshHeaderLite.faceBase else defaultValue)
			#unk06: (if meshHeaderLite.unk06 != undefined then meshHeaderLite.unk06 else defaultValue)
			#unk07: (if meshHeaderLite.unk07 != undefined then meshHeaderLite.unk07 else defaultValue)
			#vertStart2: (if meshHeaderLite.vertStart2 != undefined then meshHeaderLite.vertStart2 else defaultValue)
			#weightmaps: (if meshHeaderLite.weightmaps != undefined then meshHeaderLite.weightmaps else defaultValue)
			#bonemapindex: (if meshHeaderLite.bonemapindex != undefined then meshHeaderLite.bonemapindex else defaultValue)
			#min_index: (if meshHeaderLite.min_index != undefined then meshHeaderLite.min_index else defaultValue)
			#max_index: (if meshHeaderLite.max_index != undefined then meshHeaderLite.max_index else defaultValue)
			#unk09: (if meshHeaderLite.unk09 != undefined then meshHeaderLite.unk09 else defaultValue)
			default: defaultValue
		)
	)
)

fn RE5_BuildHeaderOnlyOverrideInfo orgMeshInfo selectMeshHeaderInfo =
(
	local result = #(false,false,false,false,false,orgMeshInfo.MatId,orgMeshInfo.bonemapindex,orgMeshInfo.lodLevel,orgMeshInfo.unk07)
	local targetMatId = RE5_GetSelectMeshHeaderField selectMeshHeaderInfo 1 orgMeshInfo.MatId
	local targetGroup = RE5_GetSelectMeshHeaderField selectMeshHeaderInfo 2 orgMeshInfo.bonemapindex
	local targetDisplay = RE5_GetSelectMeshHeaderField selectMeshHeaderInfo 3 orgMeshInfo.unk07
	local targetLod = RE5_GetSelectMeshHeaderField selectMeshHeaderInfo 4 orgMeshInfo.lodLevel
	local changedMatId = (targetMatId != orgMeshInfo.MatId)
	local changedGroup = (targetGroup != orgMeshInfo.bonemapindex)
	local changedDisplay = (targetDisplay != orgMeshInfo.unk07)
	local changedLod = (targetLod != orgMeshInfo.lodLevel)
	local unsupportedChange = false
	if changedMatId == true and RE5ExportHeaderOnlyAllowMatId != true do unsupportedChange = true
	if changedGroup == true and RE5ExportHeaderOnlyAllowGroup != true do unsupportedChange = true
	if changedDisplay == true and RE5ExportHeaderOnlyAllowDisplayMode != true do unsupportedChange = true
	if changedLod == true and RE5ExportHeaderOnlyAllowLOD != true do unsupportedChange = true
	result[2] = changedMatId
	result[3] = changedGroup
	result[4] = changedDisplay
	result[5] = changedLod
	result[6] = targetMatId
	result[7] = targetGroup
	result[8] = targetLod
	result[9] = targetDisplay
	if RE5ExportEnableHeaderOnlyNameOverrides == true and unsupportedChange == false and (changedMatId == true or changedGroup == true or changedDisplay == true or changedLod == true) then
	(
		result[1] = true
	)
	result
)

fn RE5_HeaderOnlyAbsFloat value =
(
	if value < 0 then (-value) else value
)

fn RE5_HeaderOnlyNearlyEqualFloat a b epsilon =
(
	(RE5_HeaderOnlyAbsFloat (a - b)) <= epsilon
)

fn RE5_HeaderOnlyNearlyEqualPoint3 a b epsilon =
(
	if a == undefined or b == undefined then
		false
	else
	(
		RE5_HeaderOnlyNearlyEqualFloat a.x b.x epsilon and
		RE5_HeaderOnlyNearlyEqualFloat a.y b.y epsilon and
		RE5_HeaderOnlyNearlyEqualFloat a.z b.z epsilon
	)
)

fn RE5_HeaderOnlyWeightSortDesc a b =
(
	if a[1] > b[1] then -1
	else if a[1] < b[1] then 1
	else 0
)

fn RE5_HeaderOnlyCompactWeightRows weightRows =
(
	local compactRows = #()
	local totalWeight = 0.0
	if weightRows == undefined do return compactRows
	for rowIndex = 1 to weightRows.count do
	(
		local row = weightRows[rowIndex]
		if row != undefined and row.count >= 2 and row[2] != undefined and row[1] != undefined and row[1] > 0.0 do
			append compactRows #(row[1],row[2])
	)
	if compactRows.count > 1 do qsort compactRows RE5_HeaderOnlyWeightSortDesc
	for rowIndex = 1 to compactRows.count do totalWeight += compactRows[rowIndex][1]
	if totalWeight > 0.0 then
	(
		for rowIndex = 1 to compactRows.count do compactRows[rowIndex][1] /= totalWeight
	)
	compactRows
)

fn RE5_ReadSourceMeshFaceArray sourceFile ptrTriangle orgMeshInfo =
(
	local faceArray = #()
	local rfc = 0
	local fc = orgMeshInfo.faceCount
	local vc = orgMeshInfo.vertCount
	local vstart = orgMeshInfo.vertStart
	local vbase = vstart - 1
	local vmax = vstart + vc - 1
	local f1 = 0
	local f2 = 0
	local f3 = 0
	local fi = [0,0,0]
	local notDone = true
	if sourceFile == undefined or ptrTriangle == undefined or fc < 1 or vc < 1 do return #()
	faceArray.count = fc
	fseek sourceFile ptrTriangle #seek_set
	fseek sourceFile (orgMeshInfo.faceStart * 2) #seek_cur
	f1 = ReadShort sourceFile #unsigned
	f2 = ReadShort sourceFile #unsigned
	if f1 == undefined or f2 == undefined do return #()
	for c = 1 to fc while notDone do
	(
		f3 = ReadShort sourceFile #unsigned
		if f3 == undefined or f3 > vmax or f3 < vstart then
		(
			notDone = false
		)
		else
		(
			if (mod c 2) != 0 then
				fi = [f1,f2,f3]
			else
				fi = [f1,f3,f2]
			if f1 != f2 and f2 != f3 and f3 != f1 then
			(
				rfc += 1
				faceArray[rfc] = fi - [vbase,vbase,vbase]
			)
			f1 = f2
			f2 = f3
		)
	)
	faceArray.count = rfc
	faceArray
)

fn RE5_BuildSourceCharacterHeaderOnlyCache sourceFile ptrVertex ptrTriangle orgMeshInfo boundMin boundMax boneMap =
(
	local vertArray = #()
	local uvArray = #()
	local faceArray = #()
	local weightArray = #()
	local normalArray = #()
	local vc = orgMeshInfo.vertCount
	local bgId = orgMeshInfo.bonemapindex + 1
	local meshBoneMap = undefined
	local boundSizeX = boundMax.x - boundMin.x
	local boundSizeY = boundMax.y - boundMin.y
	local boundSizeZ = boundMax.z - boundMin.z
	if sourceFile == undefined or ptrVertex == undefined or ptrTriangle == undefined do return undefined
	if vc < 1 do return undefined
	if boneMap == undefined or bgId < 1 or bgId > boneMap.count do return undefined
	meshBoneMap = boneMap[bgId]
	if meshBoneMap == undefined do return undefined
	vertArray.count = vc
	uvArray.count = vc
	weightArray.count = vc
	normalArray.count = vc
	fseek sourceFile (ptrVertex + orgMeshInfo.vertBase) #seek_set
	fseek sourceFile (orgMeshInfo.vertStride * (orgMeshInfo.vertStart + orgMeshInfo.faceBase)) #seek_cur
	case orgMeshInfo.vertFlag of
	(
		0x08:
		(
			for c = 1 to vc do
			(
				local rawPos = [(ReadShort sourceFile), (ReadShort sourceFile), (ReadShort sourceFile)]
				local boneSlots = #()
				local tempRows = #()
				local boneWeights = #()
				local mappedRows = #()
				local normalBytes = #()
				local u1 = 0
				local v1 = 0
				vertArray[c] = [rawPos.x / 32767.0 * boundSizeX + boundMin.x, -(rawPos.z / 32767.0 * boundSizeZ + boundMin.z), rawPos.y / 32767.0 * boundSizeY + boundMin.y]
				boneSlots.count = 8
				boneWeights.count = 8
				fseek sourceFile 2 #seek_cur
				for slotIndex = 1 to 8 do boneSlots[slotIndex] = ReadByte sourceFile #unsigned
				for slotIndex = 1 to 8 do boneWeights[slotIndex] = (ReadByte sourceFile #unsigned) / 255.0
				for slotIndex = 1 to 8 do
				(
					local meshMapIndex = boneSlots[slotIndex] + 1
					local gameBoneId = 1
					if meshMapIndex >= 1 and meshMapIndex <= meshBoneMap.count and meshBoneMap[meshMapIndex] != undefined do gameBoneId = meshBoneMap[meshMapIndex] + 1
					tempRows[slotIndex] = #(boneWeights[slotIndex], gameBoneId)
				)
				if tempRows.count > 1 do qsort tempRows RE5_HeaderOnlyWeightSortDesc
				if tempRows.count > 4 do tempRows = for rowIndex = 1 to 4 collect tempRows[rowIndex]
				mappedRows = RE5_HeaderOnlyCompactWeightRows tempRows
				weightArray[c] = mappedRows
				normalBytes = [(ReadByte sourceFile #unsigned), (ReadByte sourceFile #unsigned), (ReadByte sourceFile #unsigned), (ReadByte sourceFile #unsigned)]
				normalArray[c] = [((normalBytes[1] - 127.0) / 127.0), ((normalBytes[2] - 127.0) / 127.0), ((normalBytes[3] - 127.0) / 127.0)]
				u1 = ReadShort sourceFile
				v1 = ReadShort sourceFile
				uvArray[c] = [(ReadFloat16 u1), (ReadFloat16 v1) * -1.0 + 1.0, 0.0]
			)
		)
		default:
		(
			for c = 1 to vc do
			(
				local rawPos = [(ReadShort sourceFile), (ReadShort sourceFile), (ReadShort sourceFile)]
				local rawBones = #()
				local rawWeights = #()
				local mappedRows = #()
				local normalBytes = #()
				local u1 = 0
				local v1 = 0
				vertArray[c] = [rawPos.x / 32767.0 * boundSizeX + boundMin.x, -(rawPos.z / 32767.0 * boundSizeZ + boundMin.z), rawPos.y / 32767.0 * boundSizeY + boundMin.y]
				rawBones.count = 4
				rawWeights.count = 4
				fseek sourceFile 2 #seek_cur
				for slotIndex = 1 to 4 do rawBones[slotIndex] = ReadByte sourceFile #unsigned
				for slotIndex = 1 to 4 do rawWeights[slotIndex] = (ReadByte sourceFile #unsigned) / 255.0
				if rawBones[1] == 255 then
				(
					rawBones[1] = 0
					rawBones[2] = 0
					rawBones[3] = 0
					rawBones[4] = 0
					rawWeights[1] = 1.0
					rawWeights[2] = 0.0
					rawWeights[3] = 0.0
					rawWeights[4] = 0.0
				)
				for slotIndex = 1 to 4 do
				(
					if rawWeights[slotIndex] > 0.0 then
					(
						local meshMapIndex = rawBones[slotIndex] + 1
						local gameBoneId = 1
						if meshMapIndex >= 1 and meshMapIndex <= meshBoneMap.count and meshBoneMap[meshMapIndex] != undefined do gameBoneId = meshBoneMap[meshMapIndex] + 1
						append mappedRows #(rawWeights[slotIndex], gameBoneId)
					)
				)
				weightArray[c] = RE5_HeaderOnlyCompactWeightRows mappedRows
				normalBytes = [(ReadByte sourceFile #unsigned), (ReadByte sourceFile #unsigned), (ReadByte sourceFile #unsigned), (ReadByte sourceFile #unsigned)]
				normalArray[c] = [((normalBytes[1] - 127.0) / 127.0), ((normalBytes[2] - 127.0) / 127.0), ((normalBytes[3] - 127.0) / 127.0)]
				fseek sourceFile 4 #seek_cur
				u1 = ReadShort sourceFile
				v1 = ReadShort sourceFile
				uvArray[c] = [(ReadFloat16 u1), (ReadFloat16 v1) * -1.0 + 1.0, 0.0]
				fseek sourceFile 4 #seek_cur
			)
		)
	)
	faceArray = RE5_ReadSourceMeshFaceArray sourceFile ptrTriangle orgMeshInfo
	#(vertArray, uvArray, faceArray, weightArray, normalArray)
)

fn RE5_CanUseHeaderOnlySceneMatch sourceFile ptrVertex ptrTriangle orgMeshInfo sceneCache boneCount boundMin boundMax boneMap =
(
	local sourceCache = undefined
	local sourceVerts = #()
	local sourceUV1 = #()
	local sourceFaces = #()
	local sourceWeights = #()
	local sceneVerts = #()
	local sceneUV1 = #()
	local sceneFaces = #()
	local sceneWeights = #()
	local sourceNormals = #()
	local sceneNormals = #()
	local posEpsilon = 0.0005
	local uvEpsilon = 0.0005
	local weightEpsilon = 0.005
	local normalEpsilon = 0.02
	if RE5ExportHeaderOnlyRequireSceneMatch != true do return true
	if sceneCache == undefined do return false
	if boneCount <= 0 do return false
	try (sourceCache = RE5_BuildSourceCharacterHeaderOnlyCache sourceFile ptrVertex ptrTriangle orgMeshInfo boundMin boundMax boneMap) catch(sourceCache = undefined)
	if sourceCache == undefined do return false
	sourceVerts = sourceCache[1]
	sourceUV1 = sourceCache[2]
	sourceFaces = sourceCache[3]
	sourceWeights = sourceCache[4]
	sourceNormals = sourceCache[5]
	sceneVerts = sceneCache[1]
	sceneUV1 = sceneCache[2]
	sceneFaces = sceneCache[3]
	sceneWeights = sceneCache[6]
	sceneNormals = sceneCache[5]
	if sceneVerts == undefined or sceneUV1 == undefined or sceneFaces == undefined or sceneWeights == undefined or sceneNormals == undefined do return false
	if sceneVerts.count != sourceVerts.count do return false
	if sceneUV1.count != sourceUV1.count do return false
	if sceneFaces.count != sourceFaces.count do return false
	if sceneWeights.count != sourceWeights.count do return false
	if sceneNormals.count != sourceNormals.count do return false
	for vertIndex = 1 to sourceVerts.count do
	(
		if (RE5_HeaderOnlyNearlyEqualPoint3 sceneVerts[vertIndex] sourceVerts[vertIndex] posEpsilon) != true do return false
		if (RE5_HeaderOnlyNearlyEqualPoint3 sceneUV1[vertIndex] sourceUV1[vertIndex] uvEpsilon) != true do return false
		if (RE5_HeaderOnlyNearlyEqualPoint3 sceneNormals[vertIndex] sourceNormals[vertIndex] normalEpsilon) != true do return false
	)
	for faceIndex = 1 to sourceFaces.count do
	(
		local sceneFace = sceneFaces[faceIndex]
		local sourceFace = sourceFaces[faceIndex]
		if sceneFace == undefined or sourceFace == undefined do return false
		if sceneFace.x != sourceFace.x or sceneFace.y != sourceFace.y or sceneFace.z != sourceFace.z do return false
	)
	for vertIndex = 1 to sourceWeights.count do
	(
		local sceneWeightRows = RE5_HeaderOnlyCompactWeightRows sceneWeights[vertIndex]
		local sourceWeightRows = RE5_HeaderOnlyCompactWeightRows sourceWeights[vertIndex]
		if sceneWeightRows.count != sourceWeightRows.count do return false
		for rowIndex = 1 to sourceWeightRows.count do
		(
			if sceneWeightRows[rowIndex][2] != sourceWeightRows[rowIndex][2] do return false
			if (RE5_HeaderOnlyNearlyEqualFloat sceneWeightRows[rowIndex][1] sourceWeightRows[rowIndex][1] weightEpsilon) != true do return false
		)
	)
	true
)

fn RE5_FindHeaderOnlySelectionIndices meshCount meshSelIndex bMeshSelect selectMeshInfo2 selectMeshCache sourceFile boneCount boundMin boundMax boneMap ptrVertex ptrTriangle =
(
	local headerOnlyIndexFlags = #()
	headerOnlyIndexFlags.count = meshCount
	if RE5ExportEnableAutoHeaderOnlyDetection != true do return headerOnlyIndexFlags
	if RE5ExportEnableHeaderOnlyNameOverrides != true do return headerOnlyIndexFlags
	if sourceFile == undefined do return headerOnlyIndexFlags
	for meshIndex = 1 to meshCount do
	(
		local isSelectedMesh = false
		local selectionIndex = 0
		local orgMeshInfo = undefined
		local sceneHeaderInfo = undefined
		local overrideInfo = undefined
		if bMeshSelect != undefined and meshIndex <= bMeshSelect.count do isSelectedMesh = bMeshSelect[meshIndex]
		if meshSelIndex != undefined and meshIndex <= meshSelIndex.count do selectionIndex = meshSelIndex[meshIndex]
		if isSelectedMesh == true and selectionIndex > 0 and selectMeshInfo2 != undefined and selectMeshInfo2.count >= selectionIndex then
		(
			sceneHeaderInfo = selectMeshInfo2[selectionIndex]
			orgMeshInfo = RE5_ReadMeshHeaderLite sourceFile
			overrideInfo = RE5_BuildHeaderOnlyOverrideInfo orgMeshInfo sceneHeaderInfo
			if overrideInfo[1] == true then
			(
				local canUseSceneMatch = false
				local sceneCache = undefined
				if selectMeshCache != undefined and selectionIndex <= selectMeshCache.count do sceneCache = selectMeshCache[selectionIndex]
				try (canUseSceneMatch = RE5_CanUseHeaderOnlySceneMatch sourceFile ptrVertex ptrTriangle orgMeshInfo sceneCache boneCount boundMin boundMax boneMap) catch(canUseSceneMatch = false)
				if canUseSceneMatch == true then
				(
					headerOnlyIndexFlags[meshIndex] = overrideInfo
					if RE5_ShouldUseExportVerboseDebug() do
						format "RE5 header-only armed: mesh % mat:% grp:% disp:% lod:%\n" meshIndex overrideInfo[2] overrideInfo[3] overrideInfo[4] overrideInfo[5]
				)
				else if RE5_ShouldUseExportVerboseDebug() then
				(
					format "RE5 header-only blocked by scene mismatch: mesh %\n" meshIndex
				)
			)
			else if RE5_ShouldUseExportVerboseDebug() and (overrideInfo[2] == true or overrideInfo[3] == true or overrideInfo[4] == true or overrideInfo[5] == true) then
			(
				format "RE5 header-only blocked: mesh % mat:% grp:% disp:% lod:% allow=[%,%,%,%]\n" meshIndex overrideInfo[2] overrideInfo[3] overrideInfo[4] overrideInfo[5] RE5ExportHeaderOnlyAllowMatId RE5ExportHeaderOnlyAllowGroup RE5ExportHeaderOnlyAllowDisplayMode RE5ExportHeaderOnlyAllowLOD
			)
		)
		else
		(
			orgMeshInfo = RE5_ReadMeshHeaderLite sourceFile
		)
	)
	headerOnlyIndexFlags
)

fn RE5_GetExportActionModMeshId = 0
fn RE5_GetExportActionForceLOD0Id = 1
fn RE5_GetExportActionDeleteId = 2
fn RE5_GetExportActionNoTargetId = -1

fn RE5_GetManualHeaderOnlyModeLod0Id = 1
fn RE5_GetManualHeaderOnlyModeMatIdId = 2
fn RE5_GetManualHeaderOnlyModeGroupId = 3
fn RE5_GetManualHeaderOnlyModeDisplayModeId = 4

fn RE5_GetManualHeaderOnlyModeLabel modeId =
(
	case modeId of
	(
		2: "MAT_ID"
		4: "DISPLAYMODE"
		default: "LOD=0"
	)
)

fn RE5_GetSafeManualHeaderOnlyMode modeId =
(
	local safeMode = 1
	try (safeMode = modeId as integer) catch(safeMode = 1)
	if safeMode != 1 and safeMode != 2 and safeMode != 4 do safeMode = 1
	safeMode
)

fn RE5_GetManualHeaderOnlyDropdownSelection modeId =
(
	local safeMode = RE5_GetSafeManualHeaderOnlyMode modeId
	case safeMode of
	(
		2: 2
		4: 3
		default: 1
	)
)

fn RE5_CanBuildImportedSceneMesh meshInfo meshVerts meshFaces meshUVs =
(
	if meshInfo == undefined do return false
	if meshVerts == undefined do return false
	if meshFaces == undefined do return false
	if meshUVs == undefined do return false

	local vertCount = 0
	local faceCount = 0
	local uvCount = 0

	try (vertCount = meshInfo[1] as integer) catch(vertCount = 0)
	try (faceCount = meshFaces.count as integer) catch(faceCount = 0)
	try (uvCount = meshUVs.count as integer) catch(uvCount = 0)

	if vertCount < 1 do return false
	if faceCount < 1 do return false
	if meshVerts.count < 1 do return false
	if uvCount < 1 do return false

	true
)

fn RE5_GetExportActionLabel actionId =
(
	case actionId of
	(
		1: (RE5_UIStr "MESH NAME字段直写" "MESH-NAME FIELDS ONLY")
		2: (RE5_UIStr "删除" "DELETE")
		default: (RE5_UIStr "MOD MESH" "MOD MESH")
	)
)

fn RE5_TryBuildManualExportActionCandidate theNode meshCount =
(
	local result = undefined
	local sName = #()
	local meshIndex = 0
	local meshHeaderInfo = #(0,0,0,0)
	local hasSkin = false
	local vertexType = ""
	if theNode == undefined do return undefined
	try (sName = filterString theNode.name "_") catch(sName = #())
	if sName == undefined or sName.count < 3 do return undefined
	try (meshIndex = sName[2] as integer) catch(meshIndex = 0)
	if meshIndex < 1 or meshIndex > meshCount do return undefined
	try (vertexType = sName[3] as string) catch(vertexType = "")
	if vertexType == undefined or vertexType == "" do return undefined
	try (hasSkin = (theNode.modifiers[#skin] != undefined)) catch(hasSkin = false)
	if sName.count >= 7 do
	(
		try
		(
			local mshHdr_matid = 0
			local mshHdr_grp = 0
			local mshHdr_mde = 0
			local mshHdr_lod = 0
			local matTokens = filterString sName[5] "x"
			local grpTokens = filterString sName[6] "x"
			local mdeTokens = filterString sName[7] "x"
			local lodTokens = filterString sName[4] "x"
			if matTokens != undefined and matTokens.count >= 2 do mshHdr_matid = (matTokens[2] as integer)
			if grpTokens != undefined and grpTokens.count >= 2 do mshHdr_grp = (grpTokens[2] as integer)
			if mdeTokens != undefined and mdeTokens.count >= 2 do mshHdr_mde = (mdeTokens[2] as integer)
			if lodTokens != undefined and lodTokens.count >= 2 do mshHdr_lod = (lodTokens[2] as integer)
			meshHeaderInfo = #(mshHdr_matid,mshHdr_grp,mshHdr_mde,mshHdr_lod)
		)
		catch(meshHeaderInfo = #(0,0,0,0))
	)
	result = #(theNode,meshIndex,vertexType,meshHeaderInfo,hasSkin,RE5_GetExportActionModMeshId())
	result
)

fn RE5_ManualExportActionSort a b =
(
	if a[2] < b[2] then -1
	else if a[2] > b[2] then 1
	else 0
)

fn RE5_BuildManualExportActionCandidates meshCount =
(
	local result = #()
	local seen = #()
	seen.count = meshCount
	for i = 1 to meshCount do seen[i] = false
	for theNode in selection do
	(
		local item = RE5_TryBuildManualExportActionCandidate theNode meshCount
		if item != undefined do
		(
			local meshIndex = item[2]
			if meshIndex >= 1 and meshIndex <= meshCount and seen[meshIndex] != true do
			(
				seen[meshIndex] = true
				append result item
			)
		)
	)
	if result.count > 1 do qsort result RE5_ManualExportActionSort
	result
)

fn RE5_BuildExportSelectionCandidates meshCount manualExportActionMode =
(
	local result = #()
	if manualExportActionMode == #ok then
	(
		for item in RE5ManualExportActionCandidates do
		(
			if item != undefined and item.count >= 6 and item[6] == RE5_GetExportActionModMeshId() do append result item
		)
	)
	else
	(
		result = RE5_BuildManualExportActionCandidates meshCount
	)
	if result == undefined do result = #()
	if result.count > 1 do qsort result RE5_ManualExportActionSort
	result
)

fn RE5_BuildHeaderOnlySelectionCandidates meshCount manualExportActionMode =
(
	local result = #()
	if manualExportActionMode != #ok do return result
	for item in RE5ManualExportActionCandidates do
	(
		if item != undefined and item.count >= 6 and item[6] == RE5_GetExportActionForceLOD0Id() do append result item
	)
	if result.count > 1 do qsort result RE5_ManualExportActionSort
	result
)

fn RE5_BuildManualExportActionItemText actionItem =
(
	local meshIndexText = "0"
	local nodeName = ""
	local skinText = ""
	if actionItem == undefined do return ""
	try (meshIndexText = paddstring 3 actionItem[2]) catch(meshIndexText = (actionItem[2] as string))
	try (nodeName = actionItem[1].name as string) catch(nodeName = "")
	if actionItem[5] == true then
		skinText = (RE5_UIStr "带Skin" "Skin")
	else
		skinText = (RE5_UIStr "无Skin" "NoSkin")
	("MESH " + meshIndexText + " | " + skinText + " | " + nodeName)
)

fn RE5_BuildManualExportActionMap meshCount actionItems =
(
	local result = #()
	result.count = meshCount
	for i = 1 to meshCount do result[i] = RE5_GetExportActionModMeshId()
	if actionItems == undefined do return result
	for item in actionItems do
	(
		if item != undefined and item.count >= 6 do
		(
			local meshIndex = item[2]
			if meshIndex >= 1 and meshIndex <= meshCount do result[meshIndex] = item[6]
		)
	)
	result
)

fn RE5_ValidateManualExportActionCandidates actionItems =
(
	local duplicateMeshIndices = #()
	local seenFlags = #()
	local maxMeshIndex = 0
	if actionItems == undefined do return #(true, duplicateMeshIndices)
	for item in actionItems do
	(
		if item != undefined and item.count >= 2 and item[2] != undefined do
		(
			local meshIndex = 0
			try (meshIndex = item[2] as integer) catch(meshIndex = 0)
			if meshIndex > maxMeshIndex do maxMeshIndex = meshIndex
		)
	)
	if maxMeshIndex < 1 do return #(true, duplicateMeshIndices)
	seenFlags.count = maxMeshIndex
	for i = 1 to maxMeshIndex do seenFlags[i] = false
	for item in actionItems do
	(
		if item != undefined and item.count >= 2 and item[2] != undefined do
		(
			local meshIndex = 0
			try (meshIndex = item[2] as integer) catch(meshIndex = 0)
			if meshIndex > 0 then
			(
				if seenFlags[meshIndex] == true then
					appendIfUnique duplicateMeshIndices meshIndex
				else
					seenFlags[meshIndex] = true
			)
		)
	)
	#(duplicateMeshIndices.count < 1, duplicateMeshIndices)
)

fn RE5_BuildNodeParentChainText theNode =
(
	local nameChain = #()
	local currentNode = theNode
	local result = ""
	while currentNode != undefined do
	(
		local currentName = ""
		try (currentName = currentNode.name as string) catch(currentName = "")
		if currentName == "" do currentName = "<unnamed>"
		insertItem currentName nameChain 1
		try (currentNode = currentNode.parent) catch(currentNode = undefined)
	)
	for i = 1 to nameChain.count do
	(
		if i > 1 do result += " > "
		result += nameChain[i]
	)
	result
)

fn RE5_BuildNodeDirectChildrenText theNode =
(
	local childNames = #()
	local result = ""
	if theNode == undefined do return (RE5_UIStr "<无直接子节点>" "<no direct children>")
	try
	(
		for childNode in theNode.children do
		(
			local childName = ""
			try (childName = childNode.name as string) catch(childName = "")
			if childName == "" do childName = "<unnamed>"
			append childNames childName
		)
	)
	catch()
	if childNames.count < 1 do return (RE5_UIStr "<无直接子节点>" "<no direct children>")
	for childIndex = 1 to childNames.count do
	(
		if childIndex > 1 do result += ", "
		result += childNames[childIndex]
	)
	result
)

fn RE5_BuildNodeHierarchyText theNode =
(
	local parentChainText = ""
	local childText = ""
	try (parentChainText = RE5_BuildNodeParentChainText theNode) catch(parentChainText = "")
	try (childText = RE5_BuildNodeDirectChildrenText theNode) catch(childText = "")
	if parentChainText == "" do parentChainText = RE5_UIStr "<未知层级>" "<unknown hierarchy>"
	if childText == "" do childText = RE5_UIStr "<无直接子节点>" "<no direct children>"
	((RE5_UIStr "层级: " "Hierarchy: ") + parentChainText + "\r\n" + (RE5_UIStr "直接子节点: " "Direct children: ") + childText)
)

fn RE5_IsOtherMeshHierarchyNode theNode =
(
	local currentNode = theNode
	while currentNode != undefined do
	(
		local currentName = ""
		try (currentName = currentNode.name as string) catch(currentName = "")
		if currentName == "OtherMesh" do return true
		try (currentNode = currentNode.parent) catch(currentNode = undefined)
	)
	false
)

fn RE5_BuildManualExportGuidanceRulesText =
(
	local result = RE5_UIStr "以下经验来自 RE6 Modding" "The following guidance comes from RE6 modding"
	result += (RE5_UIStr "\r\n\r\n1) 非 OtherMesh 层级" "\r\n\r\n1) Outside OtherMesh")
	result += (RE5_UIStr "\r\n如果节点有可编辑网格，并且带 Skin，但在 Max 视窗里看不出几何体，建议保留，不推荐改成 LOD 0，也不建议删除；否则可能导致游戏里 MOD 不显示，需要你自行测试。" "\r\nIf a node has editable geometry and Skin, but no visible geometry in the Max viewport, it is usually safer to keep it. Do not rush to force LOD 0 or delete it, or the in-game mod may disappear. Test it yourself.")
	result += (RE5_UIStr "\r\n\r\n2) OtherMesh 层级" "\r\n\r\n2) Under OtherMesh")
	result += (RE5_UIStr "\r\n无论带不带 Skin、无论视窗里能不能看到几何体，一律更建议用 LOD 0，而不是删除 MESH；否则可能导致游戏里 MOD 不显示，需要你自行测试。" "\r\nWhether it has Skin or not, and whether geometry is visible or not, it is generally safer to use LOD 0 instead of deleting the mesh. Deleting it may cause the in-game mod to disappear. Test it yourself.")
	result += (RE5_UIStr "\r\n\r\n3) 其它情况" "\r\n\r\n3) Other cases")
	result += (RE5_UIStr "\r\n如果你遇到了其它情况，请先判断它是否符合上面两条公式化经验；如果后续发现例外，再继续修正规则。" "\r\nIf you run into another case, first decide whether it matches one of the two rule-of-thumb formulas above. If later you prove an exception, then update the rule.")
	result
)

fn RE5_BuildExportGuideText mode:#general detailText:"" =
(
	local modeValue = mode
	local extraText = ""
	local introTitle = ""
	local introText = ""
	local routeTitle = RE5_UIStr "导出三栏说明" "Three export lanes"
	local routeText = RE5_UIGetManualExportDialogHint()
	local rulesText = RE5_BuildManualExportGuidanceRulesText()
	local result = ""
	if modeValue == undefined do modeValue = #general
	try (if detailText != undefined do extraText = detailText as string) catch(extraText = "")
	case modeValue of
	(
		#forced_noskin:
		(
			introTitle = RE5_UIStr "当前问题" "Current issue"
			introText = RE5_UIStr "检测到无 Skin 的 Mesh_* 被放进了第 3 栏“修改过的 MESH”。第 3 栏会继续走传统导出并读取 Skin / 权重，所以这类节点必须先改分流。" "A no-Skin Mesh_* was placed in the third lane, Modified Meshes. That lane continues through the traditional export path and reads Skin / weights, so this node set must be rerouted first."
		)
		default:
		(
			introTitle = RE5_UIStr "导出前提示" "Before export"
			introText = RE5_UIStr "请先看下面的分流说明，再决定 Mesh_* 应该进入哪个导出栏。" "Read the routing notes below first, then decide which export lane should receive each Mesh_*."
		)
	)
	result = introTitle + "\r\n" + introText
	if extraText != "" do result += ("\r\n\r\n" + (RE5_UIStr "检测详情" "Detected details") + "\r\n" + extraText)
	result += ("\r\n\r\n" + routeTitle + "\r\n" + routeText)
	result += ("\r\n\r\n" + rulesText)
	result
)

fn RE5_BuildManualExportQuickAdviceText actionItem =
(
	local theNode = undefined
	local hasSkin = false
	local inOtherMesh = false
	if actionItem != undefined and actionItem.count >= 5 do
	(
		try (theNode = actionItem[1]) catch(theNode = undefined)
		try (hasSkin = (actionItem[5] == true)) catch(hasSkin = false)
		inOtherMesh = RE5_IsOtherMeshHierarchyNode theNode
	)
	if inOtherMesh == true then
	(
		RE5_UIStr "该节点位于 OtherMesh 层级。按 RE6 Modding 经验，更建议放到第 1 栏做 LOD 0 / Header 直写，而不是删除。" "This node is under OtherMesh. Based on RE6 modding experience, lane 1 LOD 0 / header-only handling is usually safer than deleting it."
	)
	else if hasSkin == true then
	(
		RE5_UIStr "该节点不在 OtherMesh 层级，而且带 Skin。按 RE6 Modding 经验，通常应保留；如果它确实需要传统几何导出，就留在第 3 栏。" "This node is outside OtherMesh and has Skin. Based on RE6 modding experience, it is usually safer to keep it. If it still needs traditional geometry export, keep it in lane 3."
	)
	else
	(
		RE5_UIStr "该节点不在 OtherMesh 层级，也没有 Skin。它不能走第 3 栏传统导出；如果你只是想避免它影响显示，通常更建议先考虑第 1 栏 LOD 0，再自行测试，而不是直接删除。" "This node is outside OtherMesh and has no Skin. It cannot use lane 3 traditional export. If you only want to neutralize it, lane 1 LOD 0 is usually safer than deleting it, but you should still test it yourself."
	)
)

fn RE5_BuildManualExportNoSkinDetailText actionItems =
(
	local result = ""
	if actionItems != undefined and actionItems.count > 0 do
	(
		for itemIndex = 1 to actionItems.count do
		(
			local actionItem = actionItems[itemIndex]
			local meshIndexText = "000"
			local nodeName = "<unnamed>"
			local hierarchyText = ""
			local adviceText = ""
			if actionItem != undefined do
			(
				try (meshIndexText = paddstring 3 actionItem[2]) catch(meshIndexText = (actionItem[2] as string))
				try (nodeName = actionItem[1].name as string) catch(nodeName = "<unnamed>")
				try (hierarchyText = RE5_BuildNodeHierarchyText actionItem[1]) catch(hierarchyText = ((RE5_UIStr "层级: " "Hierarchy: ") + nodeName))
				try (adviceText = RE5_BuildManualExportQuickAdviceText actionItem) catch(adviceText = "")
			)
			if itemIndex > 1 do result += "\r\n\r\n"
			result += ("MESH " + meshIndexText + "\r\n")
			result += ((RE5_UIStr "节点: " "Node: ") + nodeName + "\r\n")
			result += (hierarchyText + "\r\n")
			if adviceText != "" do result += ((RE5_UIStr "建议: " "Advice: ") + adviceText)
		)
	)
	if result != "" do
	(
		result += ("\r\n\r\n" + RE5_UIStr "你可以把这些节点加入第 1 栏做 Header 直写；如果你坚持要删，也可以加入第 2 栏，但这不代表脚本推荐删除，仍请按下方普通导出指南继续判断。" "You can move these nodes into lane 1 for header-only handling. If you still insist on deleting them, you can move them into lane 2, but that does not mean the script recommends deletion. Use the ordinary export guide below before deciding.")
	)
	result
)

fn RE5_FindManualModifiedNoSkinCandidates actionItems =
(
	local result = #()
	if actionItems == undefined do return result
	for item in actionItems do
	(
		if item != undefined and item.count >= 6 do
		(
			local hasSkin = false
			try (hasSkin = (item[5] == true)) catch(hasSkin = false)
			if item[6] == RE5_GetExportActionModMeshId() and hasSkin != true do append result item
		)
	)
	if result.count > 1 do qsort result RE5_ManualExportActionSort
	result
)

fn RE5_BuildManualDeleteMeshFlags meshCount actionMap =
(
	local result = #()
	result.count = meshCount
	for i = 1 to meshCount do
	(
		result[i] = false
		if actionMap != undefined and i <= actionMap.count and actionMap[i] == RE5_GetExportActionDeleteId() do result[i] = true
	)
	result
)

fn RE5_BuildManualHeaderOnlyOverrideFlags meshCount actionMap meshSelIndex selectMeshInfo2 sourceFile =
(
	local result = #()
	result.count = meshCount
	if sourceFile == undefined do return result
	for meshIndex = 1 to meshCount do
	(
		local orgMeshHeaderLite = RE5_ReadMeshHeaderLite sourceFile
		local orgMatId = RE5_GetMeshHeaderLiteField orgMeshHeaderLite #matid 0
		local orgBoneMapIndex = RE5_GetMeshHeaderLiteField orgMeshHeaderLite #bonemapindex 0
		local orgLodLevel = RE5_GetMeshHeaderLiteField orgMeshHeaderLite #lodLevel 0
		local orgDisplayMode = RE5_GetMeshHeaderLiteField orgMeshHeaderLite #unk07 0
		if actionMap != undefined and meshIndex <= actionMap.count and actionMap[meshIndex] == RE5_GetExportActionForceLOD0Id() then
		(
			local selectionIndex = 0
			local sceneHeaderInfo = undefined
			local manualHeaderOnlyMode = RE5_GetSafeManualHeaderOnlyMode RE5ManualExportHeaderOnlyMode
			local overrideInfo = #(true,false,false,false,false,orgMatId,orgBoneMapIndex,orgLodLevel,orgDisplayMode)
			if meshSelIndex != undefined and meshIndex <= meshSelIndex.count do selectionIndex = meshSelIndex[meshIndex]
			if selectionIndex > 0 and selectMeshInfo2 != undefined and selectionIndex <= selectMeshInfo2.count do sceneHeaderInfo = selectMeshInfo2[selectionIndex]
			case manualHeaderOnlyMode of
			(
				2:
				(
					overrideInfo[2] = true
					overrideInfo[6] = RE5_GetSelectMeshHeaderField sceneHeaderInfo 1 orgMatId
				)
				4:
				(
					overrideInfo[4] = true
					overrideInfo[9] = RE5_GetSelectMeshHeaderField sceneHeaderInfo 3 orgDisplayMode
				)
				default:
				(
					overrideInfo[5] = true
					overrideInfo[8] = 0
				)
			)
			result[meshIndex] = overrideInfo
		)
	)
	result
)

fn RE5_MergeHeaderOnlyOverrideFlags primaryFlags secondaryFlags meshCount =
(
	local result = #()
	result.count = meshCount
	for i = 1 to meshCount do
	(
		result[i] = undefined
		if primaryFlags != undefined and i <= primaryFlags.count and primaryFlags[i] != undefined then
			result[i] = primaryFlags[i]
		else if secondaryFlags != undefined and i <= secondaryFlags.count and secondaryFlags[i] != undefined then
			result[i] = secondaryFlags[i]
	)
	result
)

fn RE5_DetectSystemLanguage =
(
	local detectedLang = "EN"
	local regLang = ""
	local probeText = ""
	local maxDataDir = ""
	local envLang = ""
	local regProbePath = ((getDir #temp) + "\\re5_codex_ui_lang.txt")
	try
	(
		if doesFileExist regProbePath do deleteFile regProbePath
		hiddenDOSCommand ("cmd /c reg query \"HKCU\\Control Panel\\International\" /v LocaleName > \"" + regProbePath + "\" 2>nul") startpath:(getDir #temp)
		if doesFileExist regProbePath do
		(
			local regFile = openFile regProbePath mode:"r"
			if regFile != undefined do
			(
				while not eof regFile do
				(
					local regLine = readLine regFile
					if regLine != undefined and regLine != "" do regLang += (" " + (toLower regLine))
				)
				close regFile
			)
			try (deleteFile regProbePath) catch()
		)
	)
	catch()
	if matchPattern regLang pattern:"*zh*" then return "CN"
	if (findString regLang "chinese") != undefined do return "CN"
	if (findString regLang "0804") != undefined do return "CN"
	if (findString regLang "0404") != undefined do return "CN"
	try (maxDataDir = getDir #maxData as string) catch(maxDataDir = "")
	if maxDataDir != "" do
	(
		local maxDataLower = toLower maxDataDir
		if (findString maxDataLower "\\chs\\") != undefined or (findString maxDataLower "\\zh-cn\\") != undefined or (findString maxDataLower "\\zh_cn\\") != undefined do return "CN"
		probeText += (" " + maxDataLower)
	)
	try (envLang = sysInfo.getEnvVariable "LANG") catch(envLang = "")
	if envLang == "" do try (envLang = sysInfo.getEnvVariable "LANGUAGE") catch(envLang = "")
	if envLang == "" do try (envLang = sysInfo.getEnvVariable "LC_ALL") catch(envLang = "")
	if envLang != undefined and envLang != "" do probeText += (" " + (toLower envLang))
	if (findString probeText "zh") != undefined do detectedLang = "CN"
	if (findString probeText "chinese") != undefined do detectedLang = "CN"
	detectedLang
)

fn RE5_NormalizeUILanguage langValue =
(
	local upperLang = "EN"
	try (upperLang = toUpper (langValue as string)) catch(upperLang = "EN")
	if upperLang == "ZH_CN" do upperLang = "CN"
	if upperLang != "CN" do upperLang = "EN"
	upperLang
)

fn RE5_SetUILanguage langValue manual:false =
(
	RE5UILanguage = RE5_NormalizeUILanguage langValue
	RE5UIManualLanguageOverride = manual
	RE5UILanguage
)

fn RE5_IsChineseUI =
(
	local lang = RE5UILanguage
	if lang == undefined or lang == "" do
	(
		try (lang = RE5_DetectSystemLanguage()) catch(lang = "EN")
	)
	(RE5_NormalizeUILanguage lang == "CN")
)

fn RE5_UIStr cnText enText =
(
	if RE5_IsChineseUI() == true then cnText else enText
)

fn RE5_InitRuntimeProfile =
(
	try (RE5RuntimeMaxMajor = RE5_GetMaxMajorVersion()) catch(RE5RuntimeMaxMajor = 0)
	RE5RuntimeUseBulkMeshReads = (RE5RuntimeMaxMajor >= 28)
	if RE5UILanguage == undefined or RE5UILanguage == "" do
	(
		try (RE5UILanguage = RE5_NormalizeUILanguage (RE5_DetectSystemLanguage())) catch(RE5UILanguage = "EN")
	)
	try (RE5_LoadManualExportGuideSettings()) catch()
	true
)

fn RE5_GetSettingsIniPath =
(
	if RE5SettingsIniPath == undefined or RE5SettingsIniPath == "" do
	(
		local baseDir = ""
		try (baseDir = getDir #plugcfg) catch(baseDir = "")
		if baseDir == undefined or baseDir == "" do
		(
			try (baseDir = getDir #temp) catch(baseDir = "")
		)
		RE5SettingsIniPath = (baseDir + "\\RE5_Codex_UI.ini")
	)
	RE5SettingsIniPath
)

fn RE5_ParseIniBoolValue iniValue defaultValue =
(
	local safeText = ""
	if iniValue == undefined do return defaultValue
	try (safeText = toUpper (iniValue as string)) catch(safeText = "")
	if safeText == "" do return defaultValue
	if safeText == "0" or safeText == "FALSE" or safeText == "NO" or safeText == "OFF" then false else true
)

fn RE5_LoadManualExportGuideSettings =
(
	if RE5ManualExportGuideSettingsLoaded == true do return true
	local savedValue = ""
	try (savedValue = getIniSetting (RE5_GetSettingsIniPath()) "ManualExport" "AutoShowGuide") catch(savedValue = "")
	if savedValue == undefined or savedValue == "" then
		RE5ManualExportGuideAutoShow = true
	else
		RE5ManualExportGuideAutoShow = RE5_ParseIniBoolValue savedValue true
	RE5ManualExportGuideSettingsLoaded = true
	true
)

fn RE5_SaveManualExportGuideSettings =
(
	RE5ManualExportGuideSettingsLoaded = true
	try (setIniSetting (RE5_GetSettingsIniPath()) "ManualExport" "AutoShowGuide" (if RE5ManualExportGuideAutoShow == true then "1" else "0")) catch()
	true
)

fn RE5_ReenableManualExportGuideAutoShow persist:true =
(
	RE5ManualExportGuideAutoShow = true
	RE5ManualExportGuideSettingsLoaded = true
	if persist == true do RE5_SaveManualExportGuideSettings()
	true
)

fn RE5_CommitManualExportGuideCheckboxState chkCtrl =
(
	local autoShow = true
	try (autoShow = (chkCtrl.checked != true)) catch(autoShow = true)
	RE5ManualExportGuideAutoShow = autoShow
	RE5_SaveManualExportGuideSettings()
	autoShow
)

fn RE5_ProcessUI =
(
	if RE5ImportBatchActive != true do
	(
		try (windows.processPostedMessages()) catch()
	)
	true
)

fn RE5_ResetProgressState =
(
	RE5ProgressLastValue = -1
	RE5ProgressLastText = ""
	RE5ProgressLastTick = 0
	true
)

fn RE5_SetProgress value statusText =
(
	local safeValue = 0
	local safeText = ""
	local nowTick = 0
	local shouldForce = false
	local shouldPump = false
	try (safeValue = value as integer) catch(safeValue = 0)
	try (safeText = statusText as string) catch(safeText = "")
	if safeValue < 0 do safeValue = 0
	if safeValue > 100 do safeValue = 100
	try (nowTick = (timeStamp() as integer)) catch(nowTick = 0)
	if safeValue <= 0 or safeValue >= 100 do shouldForce = true
	if safeText != RE5ProgressLastText do shouldForce = true
	if safeValue != RE5ProgressLastValue do
	(
		if (nowTick - RE5ProgressLastTick) >= RE5ProgressThrottleMs do shouldPump = true
	)
	if shouldForce == true or shouldPump == true then
	(
		RE5ProgressLastValue = safeValue
		RE5ProgressLastText = safeText
		RE5ProgressLastTick = nowTick
		try (Re5ModTool.pbMain.value = safeValue) catch()
		try (Re5ModTool.lblStatus.text = safeText) catch()
		RE5_ProcessUI()
	)
	true
)

fn RE5_BeginImportBatchOp =
(
	RE5ImportBatchActive = true
	try (disableSceneRedraw()) catch()
	try (suspendEditing()) catch()
	try (max create mode) catch()
	true
)

fn RE5_EndImportBatchOp =
(
	try (resumeEditing()) catch()
	try (enableSceneRedraw()) catch()
	RE5ImportBatchActive = false
	true
)

fn RE5_UILayoutRect ctrlName ctrlPos ctrlWidth ctrlHeight =
(
	#(ctrlName as string, ctrlPos, ctrlWidth, ctrlHeight)
)

fn RE5_UIInt value =
(
	local outValue = 0
	try (outValue = value as integer) catch(outValue = 0)
	outValue
)

fn RE5_UIEstimateTextWidth textValue =
(
	local safeText = ""
	local charWidth = 9
	local extraWidth = 0
	try (safeText = textValue as string) catch(safeText = "")
	if safeText == "" do return 0
	if RE5_IsChineseUI() == true then
	(
		charWidth = 16
		extraWidth = 2
	)
	((safeText.count * charWidth) + extraWidth)
)

fn RE5_CountWrappedLinesText textValue maxWidth =
(
	local safeText = ""
	local safeWidth = amax #(120, maxWidth)
	local lineCount = 1
	local currentWidth = 0
	if textValue == undefined do return 1
	try (safeText = textValue as string) catch(safeText = "")
	if safeText == "" do return 1
	for charIndex = 1 to safeText.count do
	(
		local ch = substring safeText charIndex 1
		local chWidth = 0
		if ch == "\r" then
		(
		)
		else if ch == "\n" then
		(
			lineCount += 1
			currentWidth = 0
		)
		else
		(
			if ch == "\t" then
				chWidth = RE5_UIEstimateTextWidth "    "
			else
				chWidth = amax #(4, RE5_UIEstimateTextWidth ch)
			if currentWidth > 0 and (currentWidth + chWidth) > safeWidth then
			(
				lineCount += 1
				currentWidth = chWidth
			)
			else
			(
				currentWidth += chWidth
			)
		)
	)
	amax #(1, lineCount)
)

fn RE5_ComputeAutoDialogTextHeight textValue contentWidth minHeight maxHeight =
(
	local lineCount = RE5_CountWrappedLinesText textValue (amax #(120, contentWidth - 18))
	local textHeight = ((lineCount * 18) + 26)
	textHeight = amax #(minHeight, textHeight)
	textHeight = amin #(maxHeight, textHeight)
	textHeight
)

fn RE5_ComputeReadOnlyTextBoxHeight textValue contentWidth minHeight maxHeight fontSize:9.25 =
(
	local safeWidth = amax #(120, contentWidth)
	local measureWidth = amax #(96, safeWidth - 26)
	local textHeight = 0
	local lineCount = 1
	local graphicsRef = undefined
	local bitmapRef = undefined
	local fontRef = undefined
	local measuredSize = undefined
	try
	(
		bitmapRef = dotNetObject "System.Drawing.Bitmap" 1 1
		graphicsRef = (dotNetClass "System.Drawing.Graphics").FromImage bitmapRef
		if RE5_IsChineseUI() == true then
			fontRef = dotNetObject "System.Drawing.Font" "Microsoft YaHei UI" fontSize
		else
			fontRef = dotNetObject "System.Drawing.Font" "Segoe UI" fontSize
		measuredSize = graphicsRef.MeasureString (if textValue == undefined then "" else (textValue as string)) fontRef measureWidth
		textHeight = (ceiling measuredSize.Height) + 18
	)
	catch(textHeight = 0)
	try (if fontRef != undefined do fontRef.Dispose()) catch()
	try (if graphicsRef != undefined do graphicsRef.Dispose()) catch()
	try (if bitmapRef != undefined do bitmapRef.Dispose()) catch()
	if textHeight <= 0 do
	(
		lineCount = RE5_CountWrappedLinesText textValue measureWidth
		textHeight = ((lineCount * 18) + 36)
	)
	textHeight = amax #(minHeight, textHeight)
	textHeight = amin #(maxHeight, textHeight)
	textHeight
)

fn RE5_ConfigureReadOnlyTextBox textBoxCtrl =
(
	local typeName = ""
	try (textBoxCtrl.Multiline = true) catch()
	try (textBoxCtrl.ReadOnly = true) catch()
	try (textBoxCtrl.WordWrap = true) catch()
	try (typeName = (((textBoxCtrl.GetType()).FullName) as string)) catch(typeName = "")
	if matchPattern typeName pattern:"*RichTextBox" ignoreCase:true then
	(
		try (textBoxCtrl.ScrollBars = (dotNetClass "System.Windows.Forms.RichTextBoxScrollBars").ForcedVertical) catch()
	)
	else
	(
		try (textBoxCtrl.ScrollBars = (dotNetClass "System.Windows.Forms.ScrollBars").Vertical) catch()
	)
	try (textBoxCtrl.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle) catch()
	try (textBoxCtrl.Cursor = (dotNetClass "System.Windows.Forms.Cursors").Arrow) catch()
	try (textBoxCtrl.AcceptsReturn = true) catch()
	try (textBoxCtrl.AcceptsTab = false) catch()
	try (textBoxCtrl.ShortcutsEnabled = true) catch()
	try (textBoxCtrl.HideSelection = true) catch()
	try (textBoxCtrl.BackColor = (dotNetClass "System.Drawing.Color").FromArgb 56 56 56) catch()
	try (textBoxCtrl.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 236 236 236) catch()
	try
	(
		if RE5_IsChineseUI() == true then
			textBoxCtrl.Font = dotNetObject "System.Drawing.Font" "Microsoft YaHei UI" 9.25
		else
			textBoxCtrl.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.25
	)
	catch()
	true
)

fn RE5_ResetReadOnlyTextBoxView textBoxCtrl =
(
	if textBoxCtrl == undefined then return false
	try (textBoxCtrl.SelectionStart = 0) catch()
	try (textBoxCtrl.SelectionLength = 0) catch()
	try (textBoxCtrl.DeselectAll()) catch()
	try (textBoxCtrl.ScrollToCaret()) catch()
	true
)

fn RE5_RefreshReadOnlyTextBoxLayout textBoxCtrl =
(
	local typeName = ""
	local clientWidth = 0
	if textBoxCtrl == undefined do return false
	try (typeName = (((textBoxCtrl.GetType()).FullName) as string)) catch(typeName = "")
	try (clientWidth = textBoxCtrl.ClientSize.Width as integer) catch(clientWidth = 0)
	if clientWidth <= 0 do try (clientWidth = textBoxCtrl.Width as integer) catch(clientWidth = 0)
	if matchPattern typeName pattern:"*RichTextBox" ignoreCase:true then
	(
		try (textBoxCtrl.RightMargin = amax #(80, clientWidth - 10)) catch()
	)
	try (textBoxCtrl.Invalidate()) catch()
	try (textBoxCtrl.Update()) catch()
	try (textBoxCtrl.Refresh()) catch()
	true
)

fn RE5_ConfigureManualExportListBox listCtrl =
(
	if listCtrl == undefined do return false
	try (listCtrl.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle) catch()
	try (listCtrl.IntegralHeight = false) catch()
	try (listCtrl.HorizontalScrollbar = true) catch()
	try (listCtrl.ScrollAlwaysVisible = true) catch()
	try (listCtrl.SelectionMode = (dotNetClass "System.Windows.Forms.SelectionMode").MultiExtended) catch()
	try (listCtrl.BackColor = (dotNetClass "System.Drawing.Color").FromArgb 56 56 56) catch()
	try (listCtrl.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 236 236 236) catch()
	try
	(
		if RE5_IsChineseUI() == true then
			listCtrl.Font = dotNetObject "System.Drawing.Font" "Microsoft YaHei UI" 9.0
		else
			listCtrl.Font = dotNetObject "System.Drawing.Font" "Segoe UI" 9.0
	)
	catch()
	true
)

fn RE5_ListBoxReplaceItems listCtrl stringItems =
(
	if listCtrl == undefined do return false
	if stringItems == undefined do stringItems = #()
	try (listCtrl.BeginUpdate()) catch()
	try (listCtrl.Items.Clear()) catch()
	if stringItems.count > 0 then
	(
		for itemText in stringItems do
		(
			try (listCtrl.Items.Add (itemText as string)) catch()
		)
	)
	try (listCtrl.ClearSelected()) catch()
	try (listCtrl.TopIndex = 0) catch()
	try (listCtrl.EndUpdate()) catch()
	true
)

fn RE5_ListBoxGetSelectedBitArray listCtrl =
(
	local outBits = #{}
	local selectedIndicesRef = undefined
	if listCtrl == undefined do return outBits
	try (selectedIndicesRef = listCtrl.SelectedIndices) catch(selectedIndicesRef = undefined)
	if selectedIndicesRef == undefined do return outBits
	try
	(
		for i = 0 to (selectedIndicesRef.Count - 1) do
		(
			local selectedIndex = 0
			try (selectedIndex = (selectedIndicesRef.Item[i] as integer) + 1) catch(selectedIndex = 0)
			if selectedIndex > 0 do outBits[selectedIndex] = true
		)
	)
	catch()
	outBits
)

fn RE5_ListBoxSelectBitArray listCtrl bitSel =
(
	local itemCount = 0
	local firstSelectedIndex = 0
	if listCtrl == undefined do return false
	if bitSel == undefined do bitSel = #{}
	try (itemCount = listCtrl.Items.Count as integer) catch(itemCount = 0)
	try (listCtrl.BeginUpdate()) catch()
	try (listCtrl.ClearSelected()) catch()
	if itemCount > 0 do
	(
		for i = 1 to itemCount do
		(
			if bitSel[i] == true do
			(
				if firstSelectedIndex == 0 do firstSelectedIndex = i
				try (listCtrl.SetSelected (i - 1) true) catch()
			)
		)
	)
	if firstSelectedIndex > 0 do try (listCtrl.TopIndex = firstSelectedIndex - 1) catch()
	try (listCtrl.EndUpdate()) catch()
	true
)

fn RE5_ListBoxSelectAll listCtrl =
(
	local itemCount = 0
	if listCtrl == undefined do return false
	try (itemCount = listCtrl.Items.Count as integer) catch(itemCount = 0)
	if itemCount < 1 do return false
	try (listCtrl.BeginUpdate()) catch()
	for i = 0 to (itemCount - 1) do try (listCtrl.SetSelected i true) catch()
	try (listCtrl.EndUpdate()) catch()
	true
)

fn RE5_ListBoxClearSelection listCtrl =
(
	if listCtrl == undefined do return false
	try (listCtrl.ClearSelected()) catch()
	true
)

fn RE5_UIMaxTextWidth textArray =
(
	local outWidth = 0
	if textArray != undefined do
	(
		for t in textArray do
		(
			outWidth = amax #(outWidth, RE5_UIEstimateTextWidth t)
		)
	)
	outWidth
)

fn RE5_UIClampInt value minValue maxValue =
(
	local safeValue = 0
	local safeMin = 0
	local safeMax = 0
	try (safeValue = value as integer) catch(safeValue = 0)
	try (safeMin = minValue as integer) catch(safeMin = 0)
	try (safeMax = maxValue as integer) catch(safeMax = safeMin)
	if safeMax < safeMin do
	(
		local swapValue = safeMin
		safeMin = safeMax
		safeMax = swapValue
	)
	if safeValue < safeMin do safeValue = safeMin
	if safeValue > safeMax do safeValue = safeMax
	safeValue
)

fn RE5_UIRectFromDotNetRect rectRef =
(
	if rectRef == undefined then return undefined
	local leftValue = 0
	local topValue = 0
	local rightValue = 0
	local bottomValue = 0
	try (leftValue = rectRef.Left) catch(leftValue = 0)
	try (topValue = rectRef.Top) catch(topValue = 0)
	try (rightValue = rectRef.Right) catch(rightValue = leftValue)
	try (bottomValue = rectRef.Bottom) catch(bottomValue = topValue)
	#(leftValue, topValue, rightValue, bottomValue)
)

fn RE5_UIGetDialogWindowBounds rolloutRef =
(
	local hwndValue = 0
	local handleRef = undefined
	local controlRef = undefined
	local boundsRef = undefined
	if rolloutRef == undefined do return undefined
	try (hwndValue = rolloutRef.hwnd as integer) catch(hwndValue = 0)
	if hwndValue == 0 do return undefined
	try
	(
		handleRef = dotNetObject "System.IntPtr" hwndValue
		controlRef = (dotNetClass "System.Windows.Forms.Control").FromHandle handleRef
		if controlRef != undefined do boundsRef = controlRef.Bounds
	)
	catch(boundsRef = undefined)
	RE5_UIRectFromDotNetRect boundsRef
)

fn RE5_UIGetWorkAreaRect rolloutRef:undefined =
(
	local leftValue = 0
	local topValue = 0
	local rightValue = 1280
	local bottomValue = 900
	local screenRef = undefined
	local rectRef = undefined
	local hwndValue = 0
	local handleRef = undefined
	if rolloutRef != undefined do
	(
		try (hwndValue = rolloutRef.hwnd as integer) catch(hwndValue = 0)
		if hwndValue != 0 do
		(
			try
			(
				handleRef = dotNetObject "System.IntPtr" hwndValue
				screenRef = (dotNetClass "System.Windows.Forms.Screen").FromHandle handleRef
			)
			catch(screenRef = undefined)
		)
	)
	try
	(
		if screenRef == undefined do screenRef = (dotNetClass "System.Windows.Forms.Screen").PrimaryScreen
		rectRef = screenRef.WorkingArea
		leftValue = rectRef.Left
		topValue = rectRef.Top
		rightValue = rectRef.Right
		bottomValue = rectRef.Bottom
	)
	catch()
	#(leftValue, topValue, rightValue, bottomValue)
)

fn RE5_UIBuildDialogSize widthValue heightValue minWidth:320 minHeight:240 margin:12 rolloutRef:undefined =
(
	local safeWidth = RE5_UIInt widthValue
	local safeHeight = RE5_UIInt heightValue
	local safeMinWidth = RE5_UIInt minWidth
	local safeMinHeight = RE5_UIInt minHeight
	local safeMargin = RE5_UIInt margin
	local workArea = RE5_UIGetWorkAreaRect rolloutRef:rolloutRef
	local maxWidth = safeWidth
	local maxHeight = safeHeight
	if workArea != undefined and workArea.count >= 4 do
	(
		maxWidth = amax #(safeMinWidth, (workArea[3] - workArea[1]) - safeMargin)
		maxHeight = amax #(safeMinHeight, (workArea[4] - workArea[2]) - safeMargin)
	)
	safeWidth = RE5_UIClampInt safeWidth safeMinWidth maxWidth
	safeHeight = RE5_UIClampInt safeHeight safeMinHeight maxHeight
	[safeWidth, safeHeight]
)

fn RE5_UIEnsureDialogVisible rolloutRef targetSize margin:12 preferTop:false topInset:24 =
(
	local safeMargin = RE5_UIInt margin
	local safeSize = targetSize
	local safePreferTop = (preferTop == true)
	local safeTopInset = amax #(safeMargin, (RE5_UIInt topInset))
	local workArea = RE5_UIGetWorkAreaRect rolloutRef:rolloutRef
	local currentPos = [0,0]
	local actualBounds = undefined
	local outerWidth = 0
	local outerHeight = 0
	local posX = 0
	local posY = 0
	local maxX = 0
	local maxY = 0
	if rolloutRef == undefined or safeSize == undefined or safeSize.count < 2 do return false
	try (SetDialogSize rolloutRef safeSize) catch()
	RE5_ProcessUI()
	actualBounds = RE5_UIGetDialogWindowBounds rolloutRef
	if actualBounds != undefined and actualBounds.count >= 4 then
	(
		outerWidth = actualBounds[3] - actualBounds[1]
		outerHeight = actualBounds[4] - actualBounds[2]
	)
	else
	(
		outerWidth = safeSize.x
		outerHeight = safeSize.y
	)
	if workArea == undefined or workArea.count < 4 do return true
	try (currentPos = GetDialogPos rolloutRef) catch(currentPos = [workArea[1], workArea[2]])
	posX = RE5_UIInt currentPos.x
	posY = RE5_UIInt currentPos.y
	if safePreferTop == true do
	(
		local preferredY = workArea[2] + safeTopInset
		posY = amin #(posY, preferredY)
	)
	maxX = (workArea[3] - outerWidth) - safeMargin
	maxY = (workArea[4] - outerHeight) - safeMargin
	posX = RE5_UIClampInt posX (workArea[1] + safeMargin) (amax #((workArea[1] + safeMargin), maxX))
	posY = RE5_UIClampInt posY (workArea[2] + safeMargin) (amax #((workArea[2] + safeMargin), maxY))
	try (SetDialogPos rolloutRef [posX, posY]) catch()
	RE5_ProcessUI()
	actualBounds = RE5_UIGetDialogWindowBounds rolloutRef
	if actualBounds != undefined and actualBounds.count >= 4 do
	(
		local overflowRight = actualBounds[3] - (workArea[3] - safeMargin)
		local overflowBottom = actualBounds[4] - (workArea[4] - safeMargin)
		if overflowRight > 0 or overflowBottom > 0 then
		(
			posX -= amax #(0, overflowRight)
			posY -= amax #(0, overflowBottom)
			posX = RE5_UIClampInt posX (workArea[1] + safeMargin) (amax #((workArea[1] + safeMargin), maxX))
			posY = RE5_UIClampInt posY (workArea[2] + safeMargin) (amax #((workArea[2] + safeMargin), maxY))
			try (SetDialogPos rolloutRef [posX, posY]) catch()
		)
	)
	true
)

fn RE5_UIApplyAutoDialogSize rolloutRef widthValue heightValue minWidth:320 minHeight:240 margin:12 preferTop:false topInset:24 =
(
	local safeSize = RE5_UIBuildDialogSize widthValue heightValue minWidth:minWidth minHeight:minHeight margin:margin rolloutRef:rolloutRef
	if rolloutRef == undefined or safeSize == undefined or safeSize.count < 2 do return false
	try (rolloutRef.width = safeSize.x) catch()
	try (rolloutRef.height = safeSize.y) catch()
	RE5_UIEnsureDialogVisible rolloutRef safeSize margin:margin preferTop:preferTop topInset:topInset
	RE5_ProcessUI()
	true
)

fn RE5_UINudgeDialogUp rolloutRef offsetY topMargin:8 =
(
	local workArea = undefined
	local currentPos = [0,0]
	local safeOffsetY = amax #(0, RE5_UIInt offsetY)
	local safeTopMargin = amax #(0, RE5_UIInt topMargin)
	local targetY = 0
	if rolloutRef == undefined do return false
	workArea = RE5_UIGetWorkAreaRect rolloutRef:rolloutRef
	try (currentPos = GetDialogPos rolloutRef) catch(currentPos = [0,0])
	targetY = (RE5_UIInt currentPos.y) - safeOffsetY
	if workArea != undefined and workArea.count >= 4 do targetY = amax #((workArea[2] + safeTopMargin), targetY)
	try (SetDialogPos rolloutRef [(RE5_UIInt currentPos.x), targetY]) catch()
	RE5_ProcessUI()
	true
)

fn RE5_UIGetImportButtonText =
(
	RE5_UIStr "导入 MOD" "ImportMod"
)

fn RE5_UIGetExportButtonText =
(
	RE5_UIStr "导出到 MOD" "ExportToMod"
)

fn RE5_UIGetGroupTitleText =
(
	RE5_UIStr "Mesh 重命名" "Mesh Rename"
)

fn RE5_UIGetValueLabelText =
(
	RE5_UIStr "值" "Value"
)

fn RE5_UIGetReplaceTitleText =
(
	RE5_UIStr "替换" "Replace"
)

fn RE5_UIGetReplaceLabels =
(
	if RE5_IsChineseUI() == true then #("LOD", "材质", "组", "显示") else #("LOD", "MAT", "Group", "Display")
)

fn RE5_UIGetRenameButtonText =
(
	RE5_UIStr "重命名选中" "Rename Selected"
)

fn RE5_UIGetManualExportDialogTitle =
(
	RE5_UIStr "导出 Mesh 动作" "Export Mesh Actions"
)

fn RE5_UIGetManualExportDialogHint =
(
	RE5_UIStr "此窗口是导出分流控制。\r\n\r\n1) 顶部栏：MESH NAME 字段直写 / Header-only Override\r\n必须先用本栏自己的“读取当前选择”把场景里的 Mesh_* 读进来，才会参与导出。当前安全开放 LOD=0、MAT_ID、DISPLAYMODE：它只会直写目标 .MOD 对应 MESH 的 Header 字段，同时保留原始几何、权重、UV 与骨骼映射，不走传统几何导出，因此更快，也适合纯 Header 改动。GROUPID 仍禁用，因为它会影响 bonemap / Skin 映射。\r\n\r\n2) 中间栏：删除栏\r\n本栏会删除所选 MESH 的几何数据，不让它继续写出到新文件里。\r\n\r\n3) 底部栏：修改过的 MESH / 传统导出栏\r\n只有本栏才会让这些 MESH 走正常的旧版 MOD MESH 导出流程。\r\n\r\n三个导出栏打开时默认为空，必须使用各栏自己的“读取当前选择”把场景中的 Mesh_* 读入后，才会参与导出。\r\n\r\nOK = 按这三栏导出\r\n关闭窗口/X = 中止当前导出" "This dialog is the export routing controller.\r\n\r\n1) Top lane: Mesh-Name-Field-Only / Header-only Override\r\nA scene Mesh_* only participates after you load it into this lane with that lane's own Read Current Selection button. The current safe options are LOD=0, MAT_ID, and DISPLAYMODE. This lane only rewrites the target .MOD mesh header fields while keeping the original geometry, weights, UVs, and bone mapping, so it skips the traditional geometry export path and stays faster. GROUPID remains disabled because it affects bonemap / skin mapping.\r\n\r\n2) Middle lane: Delete lane\r\nThis lane removes the selected mesh geometry from the exported result.\r\n\r\n3) Bottom lane: Modified Meshes / Traditional export lane\r\nOnly this lane sends meshes through the normal legacy MOD MESH export flow.\r\n\r\nAll three export lanes start empty. A scene Mesh_* only participates in export after you load it into a lane with that lane's own Read Current Selection button.\r\n\r\nOK = export with these three lists\r\nClose/X = abort this export."
)

fn RE5_UIGetManualExportGuideTitle =
(
	RE5_UIStr "导出分流指南" "Export Routing Guide"
)

fn RE5_UIGetManualExportGuideDontShowText =
(
	RE5_UIStr "以后默认不再自动弹出此指南" "Do not auto-show this guide again"
)

fn RE5_UIGetManualExportGuideOKText =
(
	RE5_UIStr "继续" "Continue"
)

fn RE5_UIGetManualExportGuideSkipText =
(
	RE5_UIStr "跳过指南" "Skip Guide"
)

fn RE5_UIGetManualExportForceTitleText =
(
	RE5_UIStr "MESH NAME字段直写的 MESH" "Mesh-Name-Field-Only Meshes"
)

fn RE5_UIGetManualExportForceModeLabelText =
(
	RE5_UIStr "MESH NAME字段" "Mesh Name Field"
)

fn RE5_UIGetManualExportForceModeItems =
(
	#("LOD=0","MAT_ID","DISPLAYMODE")
)

fn RE5_UIGetManualExportDeleteTitleText =
(
	RE5_UIStr "需要删除的 MESH" "Delete Meshes"
)

fn RE5_UIGetManualExportModifiedTitleText =
(
	RE5_UIStr "修改过的 MESH" "Modified Meshes"
)

fn RE5_UIGetManualExportMoveToForceText =
(
	RE5_UIStr "移到名称字段栏" "Move To Name-Field-Only"
)

fn RE5_UIGetManualExportMoveToDeleteText =
(
	RE5_UIStr "移到删除栏" "Move To Delete"
)

fn RE5_UIGetManualExportMoveToModifiedText =
(
	RE5_UIStr "移到修改栏" "Move To Modified"
)

fn RE5_UIGetManualExportClearButtonText =
(
	RE5_UIStr "清除" "Clear"
)

fn RE5_UIGetManualExportOKButtonText =
(
	RE5_UIStr "确定" "OK"
)

fn RE5_UIGetManualExportConflictWarningTitle =
(
	RE5_UIStr "导出分流冲突" "Export Action Conflict"
)

fn RE5_UIGetManualExportHeaderOnlyUnsafeTitle =
(
	RE5_UIStr "Header 直写受限" "Header-Only Restricted"
)

fn RE5_UIGetManualExportHeaderOnlyUnsafeText =
(
	RE5_UIStr "RE5 第一个导出栏当前只允许安全的 Header 直写项：LOD=0、MAT_ID、DISPLAYMODE。GROUPID 在 RE5 里会影响 bonemap / Skin 映射，不能走这个轻量分支。" "The first RE5 export lane only allows safe header-only items: LOD=0, MAT_ID, and DISPLAYMODE. GROUPID affects bonemap / skin mapping in RE5 and cannot use this lightweight branch."
)

fn RE5_UIBuildManualExportConflictWarning meshIndexList =
(
	local meshText = ""
	if meshIndexList != undefined and meshIndexList.count > 0 do
	(
		for listIndex = 1 to meshIndexList.count do
		(
			if listIndex > 1 do meshText += ", "
			meshText += ("MESH " + (paddstring 3 (meshIndexList[listIndex] as string)))
		)
	)
	if meshText == "" do meshText = "Unknown"
	RE5_UIStr ("检测到同一个 MESH 同时落在多个导出栏里，请先整理后再点 OK。\n冲突项: " + meshText) ("The same mesh was assigned to multiple export lanes. Fix the conflict before pressing OK.\nConflicts: " + meshText)
)

fn RE5_UIGetManualExportEmptyWarningTitle =
(
	RE5_UIStr "导出栏为空" "Empty Export Lanes"
)

fn RE5_UIGetManualExportEmptyWarningText =
(
	RE5_UIStr "当前三个导出栏都是空的。\n\n请先把至少一个 Mesh_* 读入某个导出栏，再点 OK；如果你不想继续这次导出，请关闭窗口。" "All three export lanes are currently empty.\n\nLoad at least one Mesh_* into a lane before pressing OK. If you do not want to continue this export, close the dialog."
)

fn RE5_UIGetManualExportModifiedNoSkinWarningTitle =
(
	RE5_UIStr "修改栏检测到无 Skin 节点" "Modified Lane Requires Skin"
)

fn RE5_UIGetManualExportNoSkinMoveToForceText =
(
	RE5_UIStr "加入第1栏" "Move To Lane 1"
)

fn RE5_UIGetManualExportNoSkinMoveToDeleteText =
(
	RE5_UIStr "加入第2栏" "Move To Lane 2"
)

fn RE5_UIGetManualExportNoSkinBackText =
(
	RE5_UIStr "返回检查" "Back"
)

fn RE5_UIBuildManualExportModifiedNoSkinWarning actionItems =
(
	RE5_BuildExportGuideText mode:#forced_noskin detailText:(RE5_BuildManualExportNoSkinDetailText actionItems)
)

fn RE5_UIGetManualExportSkipButtonText =
(
	RE5_UIStr "跳过" "SKIP"
)

fn RE5_UIGetProgressStatusSamples =
(
	if RE5_IsChineseUI() == true then
	(
		#("就绪", "选择 MOD", "打开源文件", "读取头信息", "准备导出", "完成")
	)
	else
	(
		#("Ready", "Choose MOD", "Open source", "Read header", "Prepare export", "Complete")
	)
)

fn RE5_UIBuildLayout =
(
	local importText = RE5_UIGetImportButtonText()
	local exportText = RE5_UIGetExportButtonText()
	local groupTitleText = RE5_UIGetGroupTitleText()
	local valueText = RE5_UIGetValueLabelText()
	local replaceTitleText = RE5_UIGetReplaceTitleText()
	local replaceLabels = RE5_UIGetReplaceLabels()
	local renameText = RE5_UIGetRenameButtonText()
	local progressSamples = RE5_UIGetProgressStatusSamples()
	local isCN = RE5_IsChineseUI()
	local outerMargin = 18
	local topY = 14
	local sectionGap = 10
	local buttonGap = 10
	local langButtonGap = 8
	local groupPadX = 22
	local groupPadTop = 28
	local groupPadBottom = 16
	local inputGap = 6
	local valueRowGap = 14
	local buttonH = if isCN then 32 else 34
	local footerH = if isCN then 32 else 34
	local langButtonH = if isCN then 22 else 24
	local inputH = 24
	local progressH = 10
	local statusH = 18
	local progressGapY = 6
	local radioTitleGap = 10
	local radioTitleH = 18
	local radioRowH = if isCN then 22 else 24
	local radioCount = replaceLabels.count
	local langCNText = "中"
	local langENText = "EN"
	local langButtonCNW = amax #(30, (RE5_UIEstimateTextWidth langCNText + 18))
	local langButtonENW = amax #(38, (RE5_UIEstimateTextWidth langENText + 18))
	local langButtonsW = langButtonCNW + langButtonGap + langButtonENW
	local buttonW = amax #(182, (RE5_UIEstimateTextWidth importText + 56), (RE5_UIEstimateTextWidth exportText + 56))
	local valueLabelW = amax #(28, RE5_UIEstimateTextWidth valueText)
	local editW = if isCN then 90 else 108
	local valueRowW = valueLabelW + inputGap + editW
	local replaceTitleW = amax #(42, RE5_UIEstimateTextWidth replaceTitleText)
	local radioContentW = amax #(replaceTitleW, (RE5_UIMaxTextWidth replaceLabels + 38))
	local groupContentW = amax #(valueRowW, radioContentW, (RE5_UIEstimateTextWidth groupTitleText + 12))
	local groupW = amax #(236, buttonW, (groupContentW + (groupPadX * 2)))
	local radioOptionsH = radioCount * radioRowH
	local groupH = groupPadTop + inputH + valueRowGap + radioTitleH + radioTitleGap + radioOptionsH + groupPadBottom
	local footerW = amax #(groupW, (RE5_UIEstimateTextWidth renameText + 60))
	local progressW = amax #(buttonW, (RE5_UIMaxTextWidth progressSamples + 24))
	local mainColumnW = amax #(buttonW, progressW, groupW, footerW, langButtonsW)
	local dialogW = mainColumnW + (outerMargin * 2)
	local columnX = RE5_UIInt ((dialogW - mainColumnW) / 2)
	local buttonX = RE5_UIInt (columnX + ((mainColumnW - buttonW) / 2))
	local progressX = RE5_UIInt (columnX + ((mainColumnW - progressW) / 2))
	local groupX = RE5_UIInt (columnX + ((mainColumnW - groupW) / 2))
	local footerX = RE5_UIInt (columnX + ((mainColumnW - footerW) / 2))
	local langButtonsX = RE5_UIInt (columnX + ((mainColumnW - langButtonsW) / 2))
	local langButtonCNX = langButtonsX
	local langButtonENX = langButtonsX + langButtonCNW + langButtonGap
	local importY = topY
	local exportY = importY + buttonH + buttonGap
	local pbY = exportY + buttonH + sectionGap
	local statusY = pbY + progressH + progressGapY
	local groupY = statusY + statusH + sectionGap
	local valueY = groupY + groupPadTop
	local labelY = valueY + 4
	local editX = groupX + groupPadX + valueLabelW + inputGap
	local replaceY = valueY + inputH + valueRowGap
	local replaceLabelY = replaceY + 2
	local radioX = groupX + groupPadX
	local radioY = replaceY + radioTitleH + radioTitleGap - 2
	local radioW = groupW - (groupPadX * 2)
	local langY = groupY + groupH + sectionGap
	local footerY = langY + langButtonH + sectionGap
	local dialogH = footerY + footerH + outerMargin
	#(
		RE5_UILayoutRect "pbMain" [progressX,pbY] progressW progressH,
		RE5_UILayoutRect "lblStatus" [progressX,statusY] progressW statusH,
		RE5_UILayoutRect "ImportButton" [buttonX,importY] buttonW buttonH,
		RE5_UILayoutRect "ExportButton" [buttonX,exportY] buttonW buttonH,
		RE5_UILayoutRect "grp3" [groupX,groupY] groupW groupH,
		RE5_UILayoutRect "lblValue" [groupX + groupPadX,labelY] valueLabelW 18,
		RE5_UILayoutRect "edt4" [editX,valueY] editW inputH,
		RE5_UILayoutRect "lblReplace" [groupX + groupPadX,replaceLabelY] replaceTitleW 18,
		RE5_UILayoutRect "rdo2" [radioX,radioY] radioW radioOptionsH,
		RE5_UILayoutRect "btnLangCN" [langButtonCNX,langY] langButtonCNW langButtonH,
		RE5_UILayoutRect "btnLangEN" [langButtonENX,langY] langButtonENW langButtonH,
		RE5_UILayoutRect "btn7" [footerX,footerY] footerW footerH
	)
)

fn RE5_UIFindLayoutRect layoutArray ctrlName =
(
	local targetName = ""
	try (targetName = ctrlName as string) catch(targetName = "")
	if layoutArray == undefined do return undefined
	for layoutRect in layoutArray do
	(
		if layoutRect != undefined and layoutRect.count >= 4 do
		(
			if layoutRect[1] == targetName do return layoutRect
		)
	)
	undefined
)

fn RE5_UIApplyLayoutByName layoutArray ctrlName =
(
	local ctrl = undefined
	local layoutRect = RE5_UIFindLayoutRect layoutArray ctrlName
	if layoutRect == undefined do return false
	try (ctrl = getProperty Re5ModTool (ctrlName as name)) catch(ctrl = undefined)
	if ctrl == undefined do return false
	try (ctrl.pos = layoutRect[2]) catch()
	try (ctrl.width = layoutRect[3]) catch()
	try (ctrl.height = layoutRect[4]) catch()
	true
)

fn RE5_UIGetLayoutBounds layoutArray =
(
	local maxRight = 0
	local maxBottom = 0
	if layoutArray != undefined do
	(
		for layoutRect in layoutArray do
		(
			if layoutRect != undefined and layoutRect.count >= 4 do
			(
				try (maxRight = amax #(maxRight, layoutRect[2].x + layoutRect[3])) catch()
				try (maxBottom = amax #(maxBottom, layoutRect[2].y + layoutRect[4])) catch()
			)
		)
	)
	#(maxRight,maxBottom)
)

fn RE5_UIGetDialogSizeForCurrentLayout =
(
	local layoutArray = RE5_UIBuildLayout()
	local bounds = RE5_UIGetLayoutBounds layoutArray
	RE5_UIBuildDialogSize (bounds[1] + 18) (bounds[2] + 18) minWidth:280 minHeight:320 margin:12
)

fn RE5_UIApplyDialogStateSize =
(
	local targetSize = RE5_UIGetDialogSizeForCurrentLayout()
	RE5_UIApplyAutoDialogSize Re5ModTool targetSize.x targetSize.y minWidth:280 minHeight:320 margin:12
)

fn RE5_UIApplyCurrentLayout =
(
	local layoutArray = RE5_UIBuildLayout()
	local ctrlArray = #()
	try (ctrlArray = Re5ModTool.controls) catch(ctrlArray = #())
	if ctrlArray != undefined do
	(
		for c in ctrlArray do
		(
			local ctrlName = ""
			try (ctrlName = c.name as string) catch(ctrlName = "")
			if ctrlName != "" do RE5_UIApplyLayoutByName layoutArray ctrlName
		)
	)
	true
)

fn RE5_GetNumMapVertsSafe theNode channel =
(
	local result = 0
	try (result = meshop.getNumMapVerts theNode channel) catch(result = 0)
	if result <= 0 and channel == 1 do try (result = getNumTVerts theNode) catch(result = 0)
	result
)

fn RE5_IsTriangleListFlag vertFlag =
(
	((bit.and vertFlag 0x80) != 0)
)

fn RE5_TryGetBulkVerts theNode =
(
	local vc = 0
	local outArray = undefined
	try (vc = getNumVerts theNode) catch(vc = 0)
	if vc < 1 do return #()
	if RE5RuntimeUseBulkMeshReads == true do
	(
		try (outArray = meshop.getVerts theNode #{1..vc}) catch(outArray = undefined)
	)
	if outArray == undefined then
	(
		outArray = #()
		outArray.count = vc
		for c = 1 to vc do
		(
			try (outArray[c] = getVert theNode c) catch(outArray[c] = [0,0,0])
		)
	)
	outArray
)

fn RE5_TryGetBulkFaces theNode =
(
	local fc = 0
	local outArray = undefined
	try (fc = getNumFaces theNode) catch(fc = 0)
	if fc < 1 do return #()
	if RE5RuntimeUseBulkMeshReads == true do
	(
		try (outArray = meshop.getFaces theNode #{1..fc}) catch(outArray = undefined)
	)
	if outArray == undefined then
	(
		outArray = #()
		outArray.count = fc
		for c = 1 to fc do
		(
			try (outArray[c] = getFace theNode c) catch(outArray[c] = [1,1,1])
		)
	)
	outArray
)

fn RE5_TryGetBulkMapVerts theNode channel =
(
	local vc = RE5_GetNumMapVertsSafe theNode channel
	local outArray = undefined
	if vc < 1 do return #()
	if RE5RuntimeUseBulkMeshReads == true do
	(
		try (outArray = meshop.getMapVerts theNode channel #{1..vc}) catch(outArray = undefined)
	)
	if outArray == undefined then
	(
		outArray = #()
		outArray.count = vc
		if channel == 1 then
		(
			for c = 1 to vc do
			(
				try (outArray[c] = getTVert theNode c) catch(outArray[c] = [0,0,0])
			)
		)
		else
		(
			for c = 1 to vc do
			(
				try (outArray[c] = meshop.getMapVert theNode channel c) catch(outArray[c] = [0,0,0])
			)
		)
	)
	outArray
)

fn RE5_BuildMeshReadCache theNode needMap2:false =
(
	local vertArray = RE5_TryGetBulkVerts theNode
	local tvertArray = RE5_TryGetBulkMapVerts theNode 1
	local faceArray = RE5_TryGetBulkFaces theNode
	local map2Array = undefined
	if needMap2 == true do map2Array = RE5_TryGetBulkMapVerts theNode 2
	#(vertArray,tvertArray,faceArray,map2Array)
)

fn RE5_WeightRowDesc a b =
(
	if a[1] > b[1] then -1
	else if a[1] < b[1] then 1
	else 0
)

fn RE5_GetVertexWeightBoneIDByName theSkin c j =
(
	local bone_id = 1
	local bone_index = 0
	local bone_name = ""
	try (bone_index = skinOps.GetVertexWeightBoneID theSkin c j) catch(bone_index = 0)
	if bone_index <= 0 do return bone_id
	try (bone_name = skinOps.GetBoneName theSkin bone_index 0) catch(bone_name = "")
	bone_id = RE5_ParseGameBoneIdFromBoneName bone_name
	bone_id
)

fn RE5_BuildSkinBoneGameIdLUT theSkin =
(
	local boneCount = 0
	local boneIdLUT = #()
	if theSkin == undefined do return boneIdLUT
	try (boneCount = skinOps.GetNumberBones theSkin) catch(boneCount = 0)
	if boneCount < 1 do return boneIdLUT
	boneIdLUT.count = boneCount
	for boneIndex = 1 to boneCount do
	(
		local boneName = ""
		try (boneName = skinOps.GetBoneName theSkin boneIndex 0) catch(boneName = "")
		boneIdLUT[boneIndex] = RE5_ParseGameBoneIdFromBoneName boneName
	)
	boneIdLUT
)

fn RE5_BuildSkinWeightCacheLegacy theNode theSkin =
(
	local vertCount = 0
	local cacheArray = #()
	if theSkin == undefined do return cacheArray
	try (max modify mode) catch()
	try (select theNode) catch()
	try (modPanel.setCurrentObject theSkin) catch()
	try (vertCount = getNumVerts theNode) catch(vertCount = 0)
	if vertCount < 1 do return cacheArray
	cacheArray.count = vertCount
	for c = 1 to vertCount do
	(
		local bc = 0
		local weightRows = #()
		try (bc = skinOps.getVertexWeightCount theSkin c) catch(bc = 0)
		weightRows.count = bc
		for j = 1 to bc do
		(
			local bb = RE5_GetVertexWeightBoneIDByName theSkin c j
			local ww = 0.0
			try (ww = skinOps.getVertexWeight theSkin c j) catch(ww = 0.0)
			weightRows[j] = #(ww,bb)
		)
		if bc > 1 do qsort weightRows RE5_WeightRowDesc
		cacheArray[c] = weightRows
	)
	cacheArray
)

fn RE5_BuildSkinWeightCache theNode theSkin =
(
	local vertCount = 0
	local cacheArray = #()
	local boneIdLUT = #()
	if theSkin == undefined do return cacheArray
	if RE5_IsExportOptimizationEnabled RE5ExportUseTop4SkinCache != true do return RE5_BuildSkinWeightCacheLegacy theNode theSkin
	try (max modify mode) catch()
	try (select theNode) catch()
	try (modPanel.setCurrentObject theSkin) catch()
	try (vertCount = getNumVerts theNode) catch(vertCount = 0)
	if vertCount < 1 do return cacheArray
	boneIdLUT = RE5_BuildSkinBoneGameIdLUT theSkin
	cacheArray.count = vertCount
	for c = 1 to vertCount do
	(
		local bc = 0
		local weightRows = #()
		try (bc = skinOps.getVertexWeightCount theSkin c) catch(bc = 0)
		if bc > 0 do weightRows.count = bc
		for j = 1 to bc do
		(
			local boneIndex = 0
			local boneId = 1
			local boneName = ""
			local weightValue = 0.0
			try (boneIndex = skinOps.GetVertexWeightBoneID theSkin c j) catch(boneIndex = 0)
			if boneIndex > 0 and boneIndex <= boneIdLUT.count and boneIdLUT[boneIndex] != undefined then
				boneId = boneIdLUT[boneIndex]
			else
			(
				try (boneName = skinOps.GetBoneName theSkin boneIndex 0) catch(boneName = "")
				boneId = RE5_ParseGameBoneIdFromBoneName boneName
			)
			try (weightValue = skinOps.getVertexWeight theSkin c j) catch(weightValue = 0.0)
			weightRows[j] = #(weightValue,boneId)
		)
		if weightRows.count > 1 do qsort weightRows RE5_WeightRowDesc
		if weightRows.count > 4 do weightRows = for weightIndex = 1 to 4 collect weightRows[weightIndex]
		cacheArray[c] = weightRows
	)
	cacheArray
)

fn RE5_BuildNormalCacheLegacy theNode vertCount theNorm =
(
	local normArray = #()
	normArray.count = vertCount
	if theNorm != undefined then
	(
		try (max modify mode) catch()
		try (select theNode) catch()
		try (modPanel.setCurrentObject theNorm) catch()
		local vnt = #{}
		for n = 1 to vertCount do
		(
			local vct = #{n}
			local normalValue = [0,0,0]
			vnt = #{}
			try (theNorm.ConvertVertexSelection vct vnt) catch(vnt = #{})
			if vnt.numberset > 0 then
			(
				local vnf = vnt as array
				if vnf.count > 0 do
				(
					local N = undefined
					try (N = theNorm.GetNormal vnf[1]) catch(N = undefined)
					if N != undefined do normalValue = [N.x,N.z,-N.y]
				)
			)
			normArray[n] = normalValue
		)
	)
	else
	(
		for n = 1 to vertCount do
		(
			local nodn = [0,0,0]
			try (nodn = getNormal theNode n) catch(nodn = [0,0,0])
			normArray[n] = [nodn.x,nodn.z,-nodn.y]
		)
	)
	normArray
)

fn RE5_BuildNormalCacheFromFaceNormalIds theNode vertCount theNorm =
(
	local normArray = #()
	local faceArray = #()
	local normalCount = 0
	local normalValues = #()
	local vertNormalIds = #()
	local mappedVertCount = 0
	normArray.count = vertCount
	if theNorm == undefined do return normArray
	faceArray = RE5_TryGetBulkFaces theNode
	if faceArray.count < 1 do return RE5_BuildNormalCacheLegacy theNode vertCount theNorm
	try (normalCount = theNorm.GetNumNormals node:theNode) catch(normalCount = 0)
	if normalCount < 1 do return RE5_BuildNormalCacheLegacy theNode vertCount theNorm
	normalValues.count = normalCount
	for normalIndex = 1 to normalCount do
	(
		local normalValue = [0,0,0]
		local fetchedNormal = undefined
		try (fetchedNormal = theNorm.GetNormal normalIndex node:theNode) catch(fetchedNormal = undefined)
		if fetchedNormal != undefined do normalValue = [fetchedNormal.x,fetchedNormal.z,-fetchedNormal.y]
		normalValues[normalIndex] = normalValue
	)
	vertNormalIds.count = vertCount
	for faceIndex = 1 to faceArray.count do
	(
		local fv = faceArray[faceIndex]
		local vertIds = #(fv.x,fv.y,fv.z)
		for cornerIndex = 1 to 3 do
		(
			local vertId = vertIds[cornerIndex]
			local normalId = 0
			try (normalId = theNorm.GetNormalID faceIndex cornerIndex node:theNode) catch(normalId = 0)
			if vertId >= 1 and vertId <= vertCount and normalId > 0 then
			(
				if vertNormalIds[vertId] == undefined or vertNormalIds[vertId] == 0 then
				(
					vertNormalIds[vertId] = normalId
					mappedVertCount += 1
				)
				else if normalId < vertNormalIds[vertId] then
				(
					vertNormalIds[vertId] = normalId
				)
			)
		)
	)
	if mappedVertCount < vertCount do return RE5_BuildNormalCacheLegacy theNode vertCount theNorm
	for vertIndex = 1 to vertCount do
	(
		local normalId = 0
		if vertIndex <= vertNormalIds.count and vertNormalIds[vertIndex] != undefined do normalId = vertNormalIds[vertIndex]
		if normalId > 0 and normalId <= normalValues.count and normalValues[normalId] != undefined then
			normArray[vertIndex] = normalValues[normalId]
		else
			normArray[vertIndex] = [0,0,0]
	)
	normArray
)

fn RE5_BuildNormalCache theNode vertCount theNorm =
(
	if theNorm != undefined and RE5_IsExportOptimizationEnabled RE5ExportOptimizeNormalCache == true then
	(
		try (return RE5_BuildNormalCacheFromFaceNormalIds theNode vertCount theNorm) catch()
	)
	RE5_BuildNormalCacheLegacy theNode vertCount theNorm
)

fn RE5_BuildExportMeshCache theNode needMap2:false useSkin:false =
(
	local meshCache = RE5_BuildMeshReadCache theNode needMap2:needMap2
	local theSkin = undefined
	local theNorm = undefined
	local vertCount = 0
	local normalCache = #()
	local skinWeightCache = #()
	local colorCache = #()
	try (vertCount = getNumVerts theNode) catch(vertCount = 0)
	try (theSkin = theNode.modifiers[#skin]) catch(theSkin = undefined)
	try (theNorm = theNode.modifiers["Edit Normals"]) catch(theNorm = undefined)
	normalCache = RE5_BuildNormalCache theNode vertCount theNorm
	if useSkin == true and theSkin != undefined do skinWeightCache = RE5_BuildSkinWeightCache theNode theSkin
	if useSkin == false and vertCount > 0 do
	(
		colorCache.count = vertCount
		for c = 1 to vertCount do
		(
			local sampleColor = black
			try (sampleColor = getVertColor theNode c) catch(sampleColor = black)
			colorCache[c] = sampleColor
		)
	)
	#(meshCache[1],meshCache[2],meshCache[3],meshCache[4],normalCache,skinWeightCache,colorCache,theSkin,theNorm)
)

fn RE5_CompactImportSkinWeights boneIds boneWeights =
(
	local validBones = #()
	local validWeights = #()
	local pairCount = 0
	local totalWeight = 0.0
	if boneIds != undefined and boneWeights != undefined then
	(
		pairCount = boneIds.count
		if boneWeights.count < pairCount do pairCount = boneWeights.count
		for wi = 1 to pairCount do
		(
			local boneId = boneIds[wi]
			local boneWeight = boneWeights[wi]
			if boneId != undefined and boneId > 0 and boneWeight != undefined and boneWeight > 0.0 do
			(
				local existingIndex = findItem validBones boneId
				if existingIndex > 0 then
					validWeights[existingIndex] += boneWeight
				else
				(
					append validBones boneId
					append validWeights boneWeight
				)
			)
		)
	)
	if validBones.count > 0 then
	(
		for wi = 1 to validWeights.count do totalWeight += validWeights[wi]
		if totalWeight > 0.0 then
		(
			for wi = 1 to validWeights.count do validWeights[wi] /= totalWeight
		)
	)
	#(validBones, validWeights)
)

fn RE5_BuildUsedImportBoneIds boneIdRows boneWeightRows =
(
	local usedBoneIds = #()
	if boneIdRows != undefined and boneWeightRows != undefined then
	(
		local rowCount = amin #(boneIdRows.count, boneWeightRows.count)
		for ri = 1 to rowCount do
		(
			local compactData = RE5_CompactImportSkinWeights boneIdRows[ri] boneWeightRows[ri]
			local validBones = compactData[1]
			for bi = 1 to validBones.count do
			(
				local boneId = validBones[bi]
				if boneId != undefined and boneId > 0 and (findItem usedBoneIds boneId) == 0 do append usedBoneIds boneId
			)
		)
	)
	usedBoneIds
)

fn RE5_ApplyDeferredImportSkin meshNode boneNodes boneLimit boneIdRows boneWeightRows =
(
	if meshNode == undefined do return false
	if boneNodes == undefined do return false
	if boneNodes.count == 0 do return false
	local theSkin = undefined
	local skinMod = skin()
	local vc = 0
	local meshVertCount = 0
	local skinBoneCount = 0
	local skinBoneGameIds = #()
	local skinBoneIdsByGameBone = #()
	local usedBoneIds = #()
	max modify mode
	select meshNode
	addModifier meshNode skinMod
	theSkin = meshNode.modifiers[#skin]
	if theSkin == undefined do return false
	if boneLimit != undefined and boneLimit > 0 do theSkin.bone_Limit = boneLimit
	usedBoneIds = RE5_BuildUsedImportBoneIds boneIdRows boneWeightRows
	if usedBoneIds == undefined or usedBoneIds.count < 1 then
	(
		for b = 1 to boneNodes.count do
		(
			local updateFlag = 0
			if b == boneNodes.count then updateFlag = -1
			skinOps.addBone theSkin boneNodes[b] updateFlag
		)
	)
	else
	(
		for usedIndex = 1 to usedBoneIds.count do
		(
			local boneId = usedBoneIds[usedIndex]
			if boneId >= 1 and boneId <= boneNodes.count and boneNodes[boneId] != undefined do
			(
				local updateFlag = 0
				if usedIndex == usedBoneIds.count then updateFlag = -1
				skinOps.addBone theSkin boneNodes[boneId] updateFlag
			)
		)
	)
	try (theSkin = meshNode.modifiers[#skin]) catch()
	try (skinBoneCount = skinOps.GetNumberBones theSkin) catch(skinBoneCount = 0)
	if skinBoneCount < 1 do return false
	try
	(
		skinBoneGameIds.count = skinBoneCount
		for sb = 1 to skinBoneCount do
		(
			local skinBoneName = skinOps.GetBoneName theSkin sb 0
			local gameBoneId = 0
			try (gameBoneId = execute ((filterString skinBoneName "_")[3])) catch(gameBoneId = 0)
			skinBoneGameIds[sb] = gameBoneId
		)
	)
	catch()
	if skinBoneGameIds.count > 0 then
	(
		local remapCount = amax #(skinBoneGameIds.count,256)
		skinBoneIdsByGameBone.count = remapCount
		for rawBone = 1 to skinBoneGameIds.count do
		(
			local gameBone = skinBoneGameIds[rawBone]
			if gameBone != undefined and gameBone > 0 and gameBone <= remapCount and skinBoneIdsByGameBone[gameBone] == undefined do
			(
				skinBoneIdsByGameBone[gameBone] = rawBone
			)
		)
	)
	try (meshVertCount = getNumVerts meshNode) catch(meshVertCount = 0)
	if boneIdRows != undefined then vc = boneIdRows.count
	if meshVertCount > 0 and vc > meshVertCount do vc = meshVertCount
	for c = 1 to vc do
	(
		local rowWeights = undefined
		local safeBones = #()
		local safeWeights = #()
		if boneWeightRows != undefined and c <= boneWeightRows.count do rowWeights = boneWeightRows[c]
		local validWeightData = RE5_CompactImportSkinWeights boneIdRows[c] rowWeights
		local validBones = validWeightData[1]
		local validWeights = validWeightData[2]
		for wi = 1 to validBones.count do
		(
			local boneId = validBones[wi]
			local skinBoneId = 0
			local boneWeight = 0.0
			if wi <= validWeights.count do boneWeight = validWeights[wi]
			if boneId != undefined then
			(
				skinBoneId = boneId
				if skinBoneIdsByGameBone != undefined and boneId >= 1 and boneId <= skinBoneIdsByGameBone.count and skinBoneIdsByGameBone[boneId] != undefined do
				(
					skinBoneId = skinBoneIdsByGameBone[boneId]
				)
			)
			if skinBoneId != undefined and skinBoneId >= 1 and skinBoneId <= skinBoneCount and boneWeight > 0.0 then
			(
				append safeBones skinBoneId
				append safeWeights boneWeight
			)
		)
		if safeBones.count > 0 then
		(
			skinOps.unNormalizeVertex theSkin c true
			skinOps.ReplaceVertexWeights theSkin c safeBones safeWeights
			skinOps.unNormalizeVertex theSkin c false
		)
	)
	try (skinOps.Invalidate theSkin 0) catch()
	update meshNode
	try (subobjectLevel = 0) catch()
	true
)

struct Header
(
	BoneCount,		--������
	MeshCount,		--Mesh��
	MatCount,		--������
	VertCount,		--������
	TriangleCount,		--����/3
	VertexIds,		
	VertexBufferSize,		
	SecondBufferSize,		-- 0
	TextureCount,
	GroupCount,
	BoneMapCount,	
	ptr_Bone,
	ptr_Group,
	ptr_Texture,
	ptr_Mesh,		--Mesh��ַ
	ptr_vertex,		--�����ַ
	ptr_SecondVertex,
	ptr_triangle,
	padding,
	EndSize
)

fn ReadHeader bstream =
(
	local H = Header ()
	H.BoneCount		  = ReadShort bstream #unsigned
	H.MeshCount		  = ReadShort bstream #unsigned
	H.MatCount		  = ReadShort bstream #unsigned
	H.VertCount		  = ReadLong bstream #unsigned
	H.TriangleCount	  = ReadLong bstream #unsigned	
	H.VertexIds		  = ReadLong bstream #unsigned	--??
	H.VertexBufferSize   = ReadLong bstream #unsigned
	H.SecondBufferSize 			 = ReadLong bstream #unsigned
	H.TextureCount 		 = ReadLong bstream #unsigned
	H.GroupCount 		 = ReadLong bstream #unsigned
	H.BoneMapCount 		 = ReadLong bstream #unsigned
	H.ptr_Bone		 = ReadLong bstream #unsigned		
	H.ptr_Group	  = ReadLong bstream #unsigned	
	H.ptr_Texture	  = ReadLong bstream #unsigned	
	H.ptr_Mesh		  = ReadLong bstream #unsigned
	H.ptr_vertex	  = ReadLong bstream #unsigned
	H.ptr_SecondVertex	  = ReadLong bstream #unsigned
	H.ptr_triangle    = ReadLong bstream #unsigned
	H.padding 	  = ReadLong bstream #unsigned
	H.EndSize 	  = ReadLong bstream #unsigned
	H
	
)	

fn ReadFixedString bstream fixedLen =
(
	local str = ""
	local length = 0
	local finished = false
	for i = 1 to fixedLen do
	(
		local c = ReadByte bstream #unsigned
		if c == 0 then finished = true
		if finished then continue	
		str += bit.intAsChar(c)			
		if c != 32 then length = i		
	)
	substring str 1 length
)

struct BoneInfo
(
	ID,					--cId;
	Parent,				--cParent;			// -1 means no parents
	Child,				--cChild;				// child id
	uk1,				--cUnknown;		physic ?
	uk2,			--fData[2];	physic ? col
	uk3,			--fData[2];	physic ?
	Trans				--vTrans;		
)
fn ReadBoneInfo bstream =
(
	local Info = BoneInfo()
	Info.ID = ReadByte bstream 
	Info.Parent = ReadByte bstream #unsigned
	Info.Child = ReadByte bstream #unsigned
	Info.uk1 = ReadByte bstream 
	Info.uk2 = ReadFloat bstream
	Info.uk3 = ReadFloat bstream
	Info.Trans = [(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream)]
	Info
)	

struct MatInfo
(
    Tex,        -- Texture indices
    hasNorMap,  -- has normal map
    hasLgtMap,  -- has light map
    hasAmbMap   -- has ambient map
)

fn ReadMatInfo bstream =
(
    local M = MatInfo()
    M.Tex = #()
    M.Tex.count = 8
    for i = 1 to 6 do  ( temp  = ReadLong bstream )
    for i = 1 to 8 do  
    ( 
        M.Tex[i]  = ReadLong bstream 
    )
    if M.Tex[2] > 0 then M.hasNorMap = true else M.hasNorMap = false        
    if M.Tex[4] > 0 then M.hasLgtMap = true else M.hasLgtMap = false       
    if M.Tex[6] > 0 then M.hasAmbMap = true else M.hasAmbMap = false
    
    for i = 1 to 26 do  --  color attributes
        temp = ReadLong bstream
    M
)

struct BoneGroup
(
	boneCount,
	boneId
)

fn ReadBoneGroup bstream =
(
	local B = BoneGroup ()
	
	B.boneCount = ReadLong bstream #unsigned
	B.boneId = #()
	for  bc = 1 to B.boneCount do 
	(
			bid = ReadByte bstream #unsigned
			append B.boneId  bid
	)
	if  B.boneCount < 32 do fseek bstream (32-B.boneCount) #seek_cur
	B
)

struct BoundInfo
(
    nx,mx,ny,my,nz,mz,cx,cy,cz
)

struct MeshHeader
(
	meshtype,
	MatId,
	unk01,
	lodLevel,		
	unk02,
	vertStride,
	vertFlag,
	unk04,	
	vertCount,
	vertEnd,
	vertStart,	
	vertBase,
	vertBase2,	
	faceStart,
	faceCount,
	faceBase,
	unk06,
	unk07,
	vertStart2,
	weightmaps,	
	bonemapindex,
	min_index,
	max_index,
	unk09	
)

fn ReadMeshHeader bstream =
(
	local M = MeshHeader ()
	M.meshtype = ReadShort bstream #unsigned		--mesh type
	M.MatId	 =	ReadShort bstream #unsigned		--mat index ????

	M.unk01		 =	ReadByte bstream #unsigned --01
	M.lodLevel	 =	ReadByte bstream #unsigned		--Lod�ȼ�
	M.unk02		 =	ReadShort bstream #unsigned --short
	M.vertStride		 =	ReadByte bstream #unsigned --short	
	M.vertFlag		 =	ReadByte bstream #unsigned --short
	M.unk04		 =	ReadShort bstream #unsigned --short
	
	M.vertCount = ReadShort bstream #unsigned	--�������
	M.vertEnd = ReadShort bstream #unsigned	--�������
	
	--M.unk04		 =	ReadByte bstream #unsigned
	--M.vertFlag	 =	ReadByte bstream #unsigned
	--M.vertStride =	ReadByte bstream #unsigned		--vertex size ÿ������ռ�õĿռ� һ�� 28 24 40 20
	--M.unk05		 =	ReadByte bstream #unsigned		--?
	
	M.vertStart	 =	ReadLong bstream #unsigned		--����List��ʼ
	M.vertBase	 =	ReadLong bstream #unsigned		--�����ַ��Ӧ mesh ƫ�� vertexoffset
	M.vertBase2	 =	ReadLong bstream #unsigned		--�����ַ��Ӧ mesh ƫ�� vertexoffset
	--M.fvfInfo	 =	ReadLong bstream #unsigned		--vertexformat
	
	M.faceStart	 =	ReadLong bstream #unsigned		--face list��ʼ
	M.faceCount	 =	ReadLong bstream #unsigned		--face����
	M.faceBase	 =	ReadLong bstream #unsigned		 --?? vertexindex2
	
	M.unk06	=	ReadByte bstream #unsigned -- byte *2
	M.unk07	=	ReadByte bstream #unsigned	
	
	M.vertStart2		 =	ReadShort bstream #unsigned -- Seond Vertex array index
	M.weightmaps		 =	ReadByte bstream #unsigned
	M.bonemapindex	 =	ReadByte bstream #unsigned
	M.min_index =	ReadByte bstream #unsigned
	M.max_index =	ReadByte bstream #unsigned
	
	M.unk09		 =  ReadLong bstream #unsigned 		--??	
	M
)	
	
--fn ReadFloat16 fstream = 
--(
--	hf=readshort fstream #unsigned
fn ReadFloat16 hf = 
(
	sign = bit.get hf 16
	exponent = (bit.shift (bit.and hf (bit.hexasint "7C00")) -10) as integer - 16
	fraction = bit.and hf (bit.hexasint "03FF")
	if sign==true then sign = 1 else sign = 0	
	exponentF = exponent + 127
	outputAsFloat = bit.or (bit.or (bit.shift fraction 13) \
	(bit.shift exponentF 23)) (bit.shift sign 31)
	return (bit.intasfloat outputasfloat)*2.0
)
fn FShort fValue =
---fn FShort_bad fValue =
(
	Src = bit.floatasint fValue
	Sign=exponent=Mantissa=0
	Sign = bit.shift Src -31
	exponent = (bit.shift (bit.and Src 0x7F800000) -23) - 127 + 15
	Mantissa = bit.and Src 0x007FFFFF
	if (exponent >= 0) and (exponent <= 30) then 
	(
		Result = bit.or (bit.shift Sign 15) (bit.or (bit.shift exponent 10) \
		(bit.shift (Mantissa + 0x00001000) -13))
	)
	else
	(
		if Src == 0 then
		(
			Result = 0
		)
		else
		(
			if exponent <= 0 then 
			(
				if exponent <= -10 then
				(
					Result = 0
				)
				else
				(
					Mantissa = bit.shift (bit.or Mantissa 0x00800000) -(1 - exponent)
					if (bit.or Mantissa 0x00001000) >= 0 do 
					(
						Mantissa = Mantissa + 0x00002000
						Result = bit.or (bit.shift Sign 15) (bit.shift Mantissa -13)
					)
				)
			)
			else 
			(
				if exponent == 255 - 127 + 15 then
				(
					if Mantissa == 0 then
					(
						Result = bit.or ((bit.shift Sign 15) (0x7C00))
					)
					else
					(
                        Result = bit.or (bit.shift Sign 15) (bit.or 0x7C00 (bit.shift Mantissa -13))
					)
				)
				else
				(
					if (bit.and Mantissa 0x00001000) >= 0 then
					(
						Mantissa = Mantissa + 0x00002000
						if (bit.and Mantissa 0x00800000) >= 0 then
						(
							Mantissa = 0
							exponent = exponent + 1
						)
					)
					if exponent >= 30 then
					(
						Result = bit.or((bit.shift Sign 15) (0x7C00))
					)
					else
					(
						Result = bit.or (bit.shift Sign 15) (bit.or (bit.shift exponent 10) (bit.shift Mantissa -13))
					)
				)
			)
		)
	)
	Result
)

fn ReadFace bstream =
(
	local F
	F = [(ReadShort bstream),(ReadShort bstream),(ReadShort bstream)]	
	F
)

try(destroydialog RE5ManualExportActionDialog)catch()
try(destroydialog RE5ManualExportGuideDialog)catch()
rollout RE5ManualExportGuideDialog "RE5 Export Guide"
(
	dotNetControl txtGuide "System.Windows.Forms.TextBox" pos:[18,18] width:536 height:236
	checkbox chkDontShow "" pos:[18,262] width:504 height:18 checked:false
	button btnGuideOK "OK" pos:[346,292] width:98 height:30
	button btnGuideSkip "SKIP" pos:[456,292] width:98 height:30 visible:false enabled:false

	fn RE5_ManualExportGuideApplyLayout guideText =
	(
		local dialogW = 592
		local leftX = 18
		local topY = 18
		local rightPad = 18
		local contentW = dialogW - leftX - rightPad
		local textH = RE5_ComputeReadOnlyTextBoxHeight guideText contentW 212 620
		local checkY = topY + textH + 10
		local buttonW = 98
		local buttonGap = 12
		local buttonY = checkY + 28
		local skipEnabled = (RE5ExportEnableManualMeshActionSkip == true)
		local btnSkipX = dialogW - rightPad - buttonW
		local btnOkX = btnSkipX - buttonGap - buttonW
		local singleOkX = (dialogW - buttonW) / 2
		local dialogH = buttonY + 40 + 18
		RE5_ConfigureReadOnlyTextBox txtGuide
		try (txtGuide.Location = dotNetObject "System.Drawing.Point" leftX topY) catch()
		try (txtGuide.Width = contentW) catch()
		try (txtGuide.Height = textH) catch()
		RE5_RefreshReadOnlyTextBoxLayout txtGuide
		try (chkDontShow.pos = [leftX, checkY]) catch()
		try (chkDontShow.width = contentW) catch()
		try (btnGuideOK.pos = [(if skipEnabled then btnOkX else singleOkX), buttonY]) catch()
		try (btnGuideSkip.pos = [btnSkipX, buttonY]) catch()
		try (btnGuideSkip.visible = skipEnabled) catch()
		try (btnGuideSkip.enabled = skipEnabled) catch()
		RE5_UIApplyAutoDialogSize RE5ManualExportGuideDialog dialogW dialogH minWidth:420 minHeight:260 margin:12
		true
	)

	fn RE5_ManualExportGuideApplyLanguage =
	(
		local guideText = RE5_BuildExportGuideText mode:#general
		try (RE5ManualExportGuideDialog.title = RE5_UIGetManualExportGuideTitle()) catch()
		try (txtGuide.text = guideText) catch()
		RE5_ResetReadOnlyTextBoxView txtGuide
		try (chkDontShow.text = RE5_UIGetManualExportGuideDontShowText()) catch()
		try (btnGuideOK.text = RE5_UIGetManualExportGuideOKText()) catch()
		try (btnGuideSkip.text = RE5_UIGetManualExportGuideSkipText()) catch()
		try (btnGuideSkip.visible = (RE5ExportEnableManualMeshActionSkip == true)) catch()
		try (btnGuideSkip.enabled = (RE5ExportEnableManualMeshActionSkip == true)) catch()
		RE5_ManualExportGuideApplyLayout guideText
		true
	)

	on RE5ManualExportGuideDialog open do
	(
		try (chkDontShow.checked = (RE5ManualExportGuideAutoShow != true)) catch()
		RE5_ManualExportGuideApplyLanguage()
	)

	on chkDontShow changed state do
	(
		RE5_CommitManualExportGuideCheckboxState chkDontShow
	)

	on btnGuideOK pressed do
	(
		RE5ManualExportGuideDialogResult = #ok
		destroyDialog RE5ManualExportGuideDialog
	)

	on btnGuideSkip pressed do
	(
		RE5ManualExportGuideDialogResult = #skip
		destroyDialog RE5ManualExportGuideDialog
	)

	on RE5ManualExportGuideDialog close do
	(
		if RE5ManualExportGuideDialogResult == undefined or RE5ManualExportGuideDialogResult == #pending do RE5ManualExportGuideDialogResult = #cancel
		RE5_CommitManualExportGuideCheckboxState chkDontShow
	)
)

fn RE5_ShowManualExportGuideDialog forceShow:false =
(
	local dialogOpen = false
	RE5_LoadManualExportGuideSettings()
	if forceShow != true and RE5ManualExportGuideAutoShow != true do return #ok
	RE5ManualExportGuideDialogResult = #pending
	try(destroyDialog RE5ManualExportGuideDialog)catch()
	createDialog RE5ManualExportGuideDialog 592 352
	dialogOpen = true
	while dialogOpen == true and RE5ManualExportGuideDialogResult == #pending do
	(
		try (dialogOpen = RE5ManualExportGuideDialog.isDisplayed) catch(dialogOpen = false)
		RE5_ProcessUI()
	)
	if RE5ManualExportGuideDialogResult == #pending do RE5ManualExportGuideDialogResult = #cancel
	RE5ManualExportGuideDialogResult
)

try(destroydialog RE5ManualExportNoSkinDialog)catch()
rollout RE5ManualExportNoSkinDialog "RE5 No-Skin Warning"
(
	dotNetControl txtNoSkin "System.Windows.Forms.TextBox" pos:[18,18] width:536 height:268
	button btnNoSkinForce "" pos:[164,294] width:118 height:30
	button btnNoSkinDelete "" pos:[292,294] width:118 height:30
	button btnNoSkinBack "" pos:[420,294] width:118 height:30

	fn RE5_ManualExportNoSkinApplyLayout warningText =
	(
		local dialogW = 592
		local leftX = 18
		local topY = 18
		local rightPad = 18
		local contentW = dialogW - leftX - rightPad
		local textH = RE5_ComputeReadOnlyTextBoxHeight warningText contentW 244 700
		local buttonW = 118
		local buttonGap = 10
		local buttonY = topY + textH + 12
		local btnBackX = dialogW - rightPad - buttonW
		local btnDeleteX = btnBackX - buttonGap - buttonW
		local btnForceX = btnDeleteX - buttonGap - buttonW
		local dialogH = buttonY + 42 + 18
		RE5_ConfigureReadOnlyTextBox txtNoSkin
		try (txtNoSkin.Location = dotNetObject "System.Drawing.Point" leftX topY) catch()
		try (txtNoSkin.Width = contentW) catch()
		try (txtNoSkin.Height = textH) catch()
		RE5_RefreshReadOnlyTextBoxLayout txtNoSkin
		try (btnNoSkinForce.pos = [btnForceX, buttonY]) catch()
		try (btnNoSkinDelete.pos = [btnDeleteX, buttonY]) catch()
		try (btnNoSkinBack.pos = [btnBackX, buttonY]) catch()
		RE5_UIApplyAutoDialogSize RE5ManualExportNoSkinDialog dialogW dialogH minWidth:460 minHeight:300 margin:12
		true
	)

	fn RE5_ManualExportNoSkinApplyLanguage =
	(
		local warningText = RE5_UIBuildManualExportModifiedNoSkinWarning RE5ManualExportNoSkinDialogItems
		try (RE5ManualExportNoSkinDialog.title = RE5_UIGetManualExportModifiedNoSkinWarningTitle()) catch()
		try (txtNoSkin.text = warningText) catch()
		RE5_ResetReadOnlyTextBoxView txtNoSkin
		try (btnNoSkinForce.text = RE5_UIGetManualExportNoSkinMoveToForceText()) catch()
		try (btnNoSkinDelete.text = RE5_UIGetManualExportNoSkinMoveToDeleteText()) catch()
		try (btnNoSkinBack.text = RE5_UIGetManualExportNoSkinBackText()) catch()
		RE5_ManualExportNoSkinApplyLayout warningText
		true
	)

	on RE5ManualExportNoSkinDialog open do
	(
		RE5_ManualExportNoSkinApplyLanguage()
	)

	on btnNoSkinForce pressed do
	(
		RE5ManualExportNoSkinDialogResult = #force
		destroyDialog RE5ManualExportNoSkinDialog
	)

	on btnNoSkinDelete pressed do
	(
		RE5ManualExportNoSkinDialogResult = #delete
		destroyDialog RE5ManualExportNoSkinDialog
	)

	on btnNoSkinBack pressed do
	(
		RE5ManualExportNoSkinDialogResult = #back
		destroyDialog RE5ManualExportNoSkinDialog
	)

	on RE5ManualExportNoSkinDialog close do
	(
		if RE5ManualExportNoSkinDialogResult == undefined or RE5ManualExportNoSkinDialogResult == #pending do RE5ManualExportNoSkinDialogResult = #back
	)
)

fn RE5_ShowManualExportNoSkinDialog actionItems =
(
	local dialogOpen = false
	RE5ManualExportNoSkinDialogItems = actionItems
	RE5ManualExportNoSkinDialogResult = #pending
	try(destroyDialog RE5ManualExportNoSkinDialog)catch()
	createDialog RE5ManualExportNoSkinDialog 592 380
	dialogOpen = true
	while dialogOpen == true and RE5ManualExportNoSkinDialogResult == #pending do
	(
		try (dialogOpen = RE5ManualExportNoSkinDialog.isDisplayed) catch(dialogOpen = false)
		RE5_ProcessUI()
	)
	if RE5ManualExportNoSkinDialogResult == #pending do RE5ManualExportNoSkinDialogResult = #back
	RE5ManualExportNoSkinDialogResult
)

rollout RE5ManualExportActionDialog "RE5 Export Mesh Actions"
(
	dotNetControl txtHint "System.Windows.Forms.TextBox" pos:[16,10] width:548 height:176
	label lblForce "" pos:[16,72] width:220 height:18
	button btnTipForce "?" pos:[244,72] width:20 height:18
	label lblForceMode "" pos:[272,72] width:84 height:18
	dropdownlist ddlForceMode "" pos:[362,68] width:202 height:6 items:#("LOD=0","MAT_ID","DISPLAYMODE") selection:1
	label lblDelete "" pos:[16,224] width:220 height:18
	button btnTipDelete "?" pos:[244,224] width:20 height:18
	label lblModified "" pos:[16,376] width:220 height:18
	button btnTipModified "?" pos:[244,376] width:20 height:18
	multilistbox mlbForce "" pos:[16,92] width:548 height:6
	multilistbox mlbDelete "" pos:[16,244] width:548 height:6
	multilistbox mlbModified "" pos:[16,396] width:548 height:6
	button btnLoadForce "" pos:[176,196] width:148 height:24
	button btnSelectAllForce "" pos:[332,196] width:112 height:24
	button btnClearForce "" pos:[452,196] width:112 height:24
	button btnLoadDelete "" pos:[176,348] width:148 height:24
	button btnSelectAllDelete "" pos:[332,348] width:112 height:24
	button btnClearDelete "" pos:[452,348] width:112 height:24
	button btnLoadModified "" pos:[176,500] width:148 height:24
	button btnSelectAllModified "" pos:[332,500] width:112 height:24
	button btnClearModified "" pos:[452,500] width:112 height:24
	button btnMoveToForce "" pos:[142,540] width:122 height:28
	button btnMoveToDelete "" pos:[278,540] width:118 height:28
	button btnMoveToModified "" pos:[410,540] width:154 height:28
	button btnOk "OK" pos:[242,578] width:96 height:30
	button btnSkip "SKIP" pos:[468,578] width:96 height:30 visible:false enabled:false

	fn RE5_ManualExportRefreshLists =
	(
		local forceItems = #()
		local deleteItems = #()
		local modItems = #()
		for item in RE5ManualExportActionCandidates do
		(
			if item != undefined and item.count >= 6 do
			(
				case item[6] of
				(
					1: append forceItems (RE5_BuildManualExportActionItemText item)
					2: append deleteItems (RE5_BuildManualExportActionItemText item)
					default: append modItems (RE5_BuildManualExportActionItemText item)
				)
			)
		)
		try (mlbForce.items = forceItems) catch()
		try (mlbDelete.items = deleteItems) catch()
		try (mlbModified.items = modItems) catch()
		true
	)

	fn RE5_ManualExportSetLoadTargetAction targetActionId =
	(
		RE5ManualExportLoadTargetActionId = targetActionId
		try (RE5_ManualExportRefreshLaneTargetLabels()) catch()
		true
	)

	fn RE5_ManualExportGetLoadTargetAction =
	(
		local safeAction = RE5_GetExportActionNoTargetId()
		try (safeAction = RE5ManualExportLoadTargetActionId as integer) catch(safeAction = RE5_GetExportActionNoTargetId())
		if safeAction != RE5_GetExportActionForceLOD0Id() and safeAction != RE5_GetExportActionDeleteId() and safeAction != RE5_GetExportActionModMeshId() do safeAction = RE5_GetExportActionNoTargetId()
		safeAction
	)

	fn RE5_ManualExportRefreshLaneTargetLabels =
	(
		local targetActionId = RE5_ManualExportGetLoadTargetAction()
		local forcePrefix = ""
		local deletePrefix = ""
		local modifiedPrefix = ""
		if targetActionId == RE5_GetExportActionForceLOD0Id() then forcePrefix = (RE5_UIStr ">> " ">> ")
		if targetActionId == RE5_GetExportActionDeleteId() then deletePrefix = (RE5_UIStr ">> " ">> ")
		if targetActionId == RE5_GetExportActionModMeshId() then modifiedPrefix = (RE5_UIStr ">> " ">> ")
		try (lblForce.text = forcePrefix + (RE5_UIGetManualExportForceTitleText())) catch()
		try (lblDelete.text = deletePrefix + (RE5_UIGetManualExportDeleteTitleText())) catch()
		try (lblModified.text = modifiedPrefix + (RE5_UIGetManualExportModifiedTitleText())) catch()
		true
	)

	fn RE5_ManualExportShowUnifiedTips =
	(
		RE5_ShowManualExportGuideDialog forceShow:true
	)

	fn RE5_ManualExportApplyLayout =
	(
		local leftX = 16
		local topY = 10
		local contentW = 548
		local laneListH = 88
		local laneGapY = 14
		local laneButtonW = 112
		local laneReadButtonW = 148
		local laneButtonGap = 8
		local hintText = ""
		local hintH = 120
		local hintMinH = 108
		local hintMaxH = 220
		local titleH = 18
		local fieldRowH = 24
		local fieldLabelW = 220
		local fieldModeLabelW = 84
		local fieldModeW = 202
		local lane1TitleY = 0
		local lane1ListY = 0
		local lane1ButtonsY = 0
		local lane2TitleY = 0
		local lane2ListY = 0
		local lane2ButtonsY = 0
		local lane3TitleY = 0
		local lane3ListY = 0
		local lane3ButtonsY = 0
		local footerY = 0
		local dialogH = 0
		local baseDialogH = 594
		local workArea = undefined
		local workAreaH = 0
		local safeHintMaxH = 0
		local hintDesiredH = 0
		local skipEnabled = (RE5ExportEnableManualMeshActionSkip == true)
		local okButtonW = 96
		local btnOkX = 356
		local btnSkipX = 468
		local singleOkX = (580 - okButtonW) / 2
		try (hintText = txtHint.text) catch(hintText = "")
		workArea = RE5_UIGetWorkAreaRect rolloutRef:RE5ManualExportActionDialog
		if workArea != undefined and workArea.count >= 4 then
			workAreaH = amax #(500, (workArea[4] - workArea[2]) - 24)
		else
			workAreaH = baseDialogH + hintMaxH
		safeHintMaxH = amin #(hintMaxH, amax #(hintMinH, workAreaH - baseDialogH))
		hintDesiredH = RE5_ComputeReadOnlyTextBoxHeight hintText contentW hintMinH safeHintMaxH fontSize:9.25
		hintH = hintDesiredH
		lane1TitleY = topY + hintH + 6
		lane1ListY = lane1TitleY + 20
		lane1ButtonsY = lane1ListY + laneListH + 8
		lane2TitleY = lane1ButtonsY + 36 + laneGapY
		lane2ListY = lane2TitleY + 20
		lane2ButtonsY = lane2ListY + laneListH + 8
		lane3TitleY = lane2ButtonsY + 36 + laneGapY
		lane3ListY = lane3TitleY + 20
		lane3ButtonsY = lane3ListY + laneListH + 8
		footerY = lane3ButtonsY + 44
		dialogH = footerY + 38 + 30 + 18
		RE5_ConfigureReadOnlyTextBox txtHint
		try (txtHint.Location = dotNetObject "System.Drawing.Point" leftX topY) catch()
		try (txtHint.Width = contentW) catch()
		try (txtHint.Height = hintH) catch()
		RE5_RefreshReadOnlyTextBoxLayout txtHint
		try (lblForce.pos = [leftX, lane1TitleY]) catch()
		try (btnTipForce.pos = [244, lane1TitleY]) catch()
		try (lblForceMode.pos = [272, lane1TitleY]) catch()
		try (ddlForceMode.pos = [362, lane1TitleY - 4]) catch()
		try (lblDelete.pos = [leftX, lane2TitleY]) catch()
		try (btnTipDelete.pos = [244, lane2TitleY]) catch()
		try (lblModified.pos = [leftX, lane3TitleY]) catch()
		try (btnTipModified.pos = [244, lane3TitleY]) catch()
		try (mlbForce.pos = [leftX, lane1ListY]) catch()
		try (mlbForce.width = contentW) catch()
		try (mlbDelete.pos = [leftX, lane2ListY]) catch()
		try (mlbDelete.width = contentW) catch()
		try (mlbModified.pos = [leftX, lane3ListY]) catch()
		try (mlbModified.width = contentW) catch()
		try (btnLoadForce.pos = [leftX + contentW - ((laneReadButtonW + (laneButtonW * 2)) + (laneButtonGap * 2)), lane1ButtonsY]) catch()
		try (btnSelectAllForce.pos = [leftX + contentW - ((laneButtonW * 2) + laneButtonGap), lane1ButtonsY]) catch()
		try (btnClearForce.pos = [leftX + contentW - laneButtonW, lane1ButtonsY]) catch()
		try (btnLoadDelete.pos = [leftX + contentW - ((laneReadButtonW + (laneButtonW * 2)) + (laneButtonGap * 2)), lane2ButtonsY]) catch()
		try (btnSelectAllDelete.pos = [leftX + contentW - ((laneButtonW * 2) + laneButtonGap), lane2ButtonsY]) catch()
		try (btnClearDelete.pos = [leftX + contentW - laneButtonW, lane2ButtonsY]) catch()
		try (btnLoadModified.pos = [leftX + contentW - ((laneReadButtonW + (laneButtonW * 2)) + (laneButtonGap * 2)), lane3ButtonsY]) catch()
		try (btnSelectAllModified.pos = [leftX + contentW - ((laneButtonW * 2) + laneButtonGap), lane3ButtonsY]) catch()
		try (btnClearModified.pos = [leftX + contentW - laneButtonW, lane3ButtonsY]) catch()
		try (btnMoveToForce.pos = [16, footerY]) catch()
		try (btnMoveToDelete.pos = [200, footerY]) catch()
		try (btnMoveToModified.pos = [384, footerY]) catch()
		try (btnOk.pos = [(if skipEnabled then btnOkX else singleOkX), footerY + 38]) catch()
		try (btnSkip.pos = [btnSkipX, footerY + 38]) catch()
		try (btnSkip.visible = skipEnabled) catch()
		try (btnSkip.enabled = skipEnabled) catch()
		RE5_UIApplyAutoDialogSize RE5ManualExportActionDialog 580 dialogH minWidth:580 minHeight:500 margin:12
		RE5_UINudgeDialogUp RE5ManualExportActionDialog 96 topMargin:8
		true
	)

	fn RE5_ManualExportApplyLanguage =
	(
		local safeMode = RE5_GetSafeManualHeaderOnlyMode RE5ManualExportHeaderOnlyMode
		local safeSelection = RE5_GetManualHeaderOnlyDropdownSelection safeMode
		try (RE5ManualExportActionDialog.title = RE5_UIGetManualExportDialogTitle()) catch()
		try (txtHint.text = RE5_UIGetManualExportDialogHint()) catch()
		try (lblForceMode.text = RE5_UIGetManualExportForceModeLabelText()) catch()
		try (ddlForceMode.items = RE5_UIGetManualExportForceModeItems()) catch()
		try (ddlForceMode.selection = safeSelection) catch()
		try (btnLoadForce.text = RE5_UIStr "读取当前选择" "Read Current Selection") catch()
		try (btnLoadDelete.text = RE5_UIStr "读取当前选择" "Read Current Selection") catch()
		try (btnLoadModified.text = RE5_UIStr "读取当前选择" "Read Current Selection") catch()
		try (btnMoveToForce.text = RE5_UIGetManualExportMoveToForceText()) catch()
		try (btnMoveToDelete.text = RE5_UIGetManualExportMoveToDeleteText()) catch()
		try (btnMoveToModified.text = RE5_UIGetManualExportMoveToModifiedText()) catch()
		try (btnSelectAllForce.text = RE5_UIStr "全选" "Select All") catch()
		try (btnClearForce.text = RE5_UIGetManualExportClearButtonText()) catch()
		try (btnSelectAllDelete.text = RE5_UIStr "全选" "Select All") catch()
		try (btnClearDelete.text = RE5_UIGetManualExportClearButtonText()) catch()
		try (btnSelectAllModified.text = RE5_UIStr "全选" "Select All") catch()
		try (btnClearModified.text = RE5_UIGetManualExportClearButtonText()) catch()
		try (btnOk.text = RE5_UIGetManualExportOKButtonText()) catch()
		try (btnSkip.text = RE5_UIGetManualExportSkipButtonText()) catch()
		try (btnTipForce.text = "?") catch()
		try (btnTipDelete.text = "?") catch()
		try (btnTipModified.text = "?") catch()
		try (btnSkip.visible = (RE5ExportEnableManualMeshActionSkip == true)) catch()
		try (btnSkip.enabled = (RE5ExportEnableManualMeshActionSkip == true)) catch()
		RE5ManualExportHeaderOnlyMode = safeMode
		RE5_ManualExportRefreshLaneTargetLabels()
		RE5_ManualExportApplyLayout()
		RE5_ResetReadOnlyTextBoxView txtHint
		true
	)

	fn RE5_ManualExportGetMatchingDisplayIndices targetActionId =
	(
		local outIndices = #()
		for itemIndex = 1 to RE5ManualExportActionCandidates.count do
		(
			local item = RE5ManualExportActionCandidates[itemIndex]
			if item != undefined and item.count >= 6 and item[6] == targetActionId do append outIndices itemIndex
		)
		outIndices
	)

	fn RE5_ManualExportHighlightLaneItems targetActionId meshIndices =
	(
		local targetList = mlbModified
		local displayIndexMap = #()
		local bitSel = #{}
		if meshIndices == undefined do meshIndices = #()
		case targetActionId of
		(
			1: targetList = mlbForce
			2: targetList = mlbDelete
			default: targetList = mlbModified
		)
		displayIndexMap = RE5_ManualExportGetMatchingDisplayIndices targetActionId
		for visibleIndex = 1 to displayIndexMap.count do
		(
			local itemIndex = displayIndexMap[visibleIndex]
			if itemIndex > 0 and itemIndex <= RE5ManualExportActionCandidates.count do
			(
				local item = RE5ManualExportActionCandidates[itemIndex]
				local meshIndex = 0
				if item != undefined and item.count >= 2 then
				(
					try (meshIndex = item[2] as integer) catch(meshIndex = 0)
					if meshIndex > 0 and (findItem meshIndices meshIndex) > 0 do bitSel[visibleIndex] = true
				)
			)
		)
		try (targetList.selection = bitSel) catch()
		true
	)

	fn RE5_ManualExportClearLaneSelections clearForce:true clearDelete:true clearModified:true =
	(
		if clearForce == true do try (mlbForce.selection = #{}) catch()
		if clearDelete == true do try (mlbDelete.selection = #{}) catch()
		if clearModified == true do try (mlbModified.selection = #{}) catch()
		true
	)

	fn RE5_ManualExportBuildSelectionCandidatesFromScene meshCount =
	(
		local outIndices = #()
		local loadedItems = RE5_BuildManualExportActionCandidates meshCount
		if loadedItems == undefined do return outIndices
		for loadedItem in loadedItems do
		(
			if loadedItem != undefined and loadedItem.count >= 2 do
			(
				local targetMeshIndex = 0
				try (targetMeshIndex = loadedItem[2] as integer) catch(targetMeshIndex = 0)
				if targetMeshIndex > 0 then
				(
					for itemIndex = 1 to RE5ManualExportActionCandidates.count do
					(
						if RE5ManualExportActionCandidates[itemIndex] != undefined and RE5ManualExportActionCandidates[itemIndex].count >= 2 and RE5ManualExportActionCandidates[itemIndex][2] == targetMeshIndex then
						(
							appendIfUnique outIndices itemIndex
							exit
						)
					)
				)
			)
		)
		outIndices
	)

	fn RE5_ManualExportCollectSelectedCandidateIndices sourceList =
	(
		local outIndices = #()
		local selBits = undefined
		local sourceActionId = RE5_GetExportActionModMeshId()
		local displayIndexMap = #()
		try (selBits = sourceList.selection) catch(selBits = undefined)
		if selBits == undefined do return outIndices
		if sourceList == mlbForce then sourceActionId = RE5_GetExportActionForceLOD0Id()
		else if sourceList == mlbDelete then sourceActionId = RE5_GetExportActionDeleteId()
		displayIndexMap = RE5_ManualExportGetMatchingDisplayIndices sourceActionId
		for visibleIndex = 1 to displayIndexMap.count do
		(
			if selBits[visibleIndex] == true do
			(
				append outIndices displayIndexMap[visibleIndex]
			)
		)
		outIndices
	)

	fn RE5_ManualExportMoveSelections sourceLists targetActionId =
	(
		local moveIndices = #()
		local movedMeshIndices = #()
		if sourceLists == undefined do return false
		for sourceList in sourceLists do
		(
			local sourceIndices = RE5_ManualExportCollectSelectedCandidateIndices sourceList
			if sourceIndices != undefined and sourceIndices.count > 0 do join moveIndices sourceIndices
		)
		if moveIndices.count < 1 do moveIndices = RE5_ManualExportBuildSelectionCandidatesFromScene RE5ManualExportActionMeshCount
		if moveIndices.count < 1 do return false
		if moveIndices.count > 1 do moveIndices = makeUniqueArray moveIndices
		for itemIndex in moveIndices do
		(
			if RE5ManualExportActionCandidates[itemIndex] != undefined and RE5ManualExportActionCandidates[itemIndex].count >= 6 do
			(
				local meshIndex = 0
				try (meshIndex = RE5ManualExportActionCandidates[itemIndex][2] as integer) catch(meshIndex = 0)
				RE5ManualExportActionCandidates[itemIndex][6] = targetActionId
				if meshIndex > 0 do appendIfUnique movedMeshIndices meshIndex
			)
		)
		RE5_ManualExportClearLaneSelections()
		RE5_ManualExportRefreshLists()
		RE5_ManualExportHighlightLaneItems targetActionId movedMeshIndices
		true
	)

	fn RE5_ManualExportSelectLaneAll sourceList =
	(
		local itemCount = 0
		try (itemCount = sourceList.items.count) catch(itemCount = 0)
		if itemCount < 1 do return false
		try (sourceList.selection = #{1..itemCount}) catch()
		true
	)

	fn RE5_ManualExportClearLane laneActionId =
	(
		local cleared = false
		for itemIndex = 1 to RE5ManualExportActionCandidates.count do
		(
			if RE5ManualExportActionCandidates[itemIndex] != undefined and RE5ManualExportActionCandidates[itemIndex].count >= 6 and RE5ManualExportActionCandidates[itemIndex][6] == laneActionId do
			(
				RE5ManualExportActionCandidates[itemIndex][6] = RE5_GetExportActionModMeshId()
				cleared = true
			)
		)
		RE5_ManualExportClearLaneSelections()
		if cleared == true do RE5_ManualExportRefreshLists()
		cleared
	)

	fn RE5_ManualExportClearModifiedSelection =
	(
		local cleared = false
		for itemIndex = RE5ManualExportActionCandidates.count to 1 by -1 do
		(
			if RE5ManualExportActionCandidates[itemIndex] != undefined and RE5ManualExportActionCandidates[itemIndex].count >= 6 and RE5ManualExportActionCandidates[itemIndex][6] == RE5_GetExportActionModMeshId() do
			(
				deleteItem RE5ManualExportActionCandidates itemIndex
				cleared = true
			)
		)
		RE5_ManualExportClearLaneSelections clearForce:false clearDelete:false clearModified:true
		if cleared == true do RE5_ManualExportRefreshLists()
		cleared
	)

	fn RE5_ManualExportMoveActionItemsToLane actionItems targetActionId =
	(
		local changed = false
		local movedMeshIndices = #()
		if actionItems == undefined or actionItems.count < 1 do return false
		for moveItem in actionItems do
		(
			if moveItem != undefined and moveItem.count >= 2 do
			(
				local targetMeshIndex = 0
				try (targetMeshIndex = moveItem[2] as integer) catch(targetMeshIndex = 0)
				if targetMeshIndex > 0 then
				(
					for itemIndex = 1 to RE5ManualExportActionCandidates.count do
					(
						if RE5ManualExportActionCandidates[itemIndex] != undefined and RE5ManualExportActionCandidates[itemIndex].count >= 6 and RE5ManualExportActionCandidates[itemIndex][2] == targetMeshIndex then
						(
							RE5ManualExportActionCandidates[itemIndex][6] = targetActionId
							appendIfUnique movedMeshIndices targetMeshIndex
							changed = true
							exit
						)
					)
				)
			)
		)
		if changed == true do
		(
			RE5_ManualExportRefreshLists()
			RE5_ManualExportHighlightLaneItems targetActionId movedMeshIndices
		)
		changed
	)

	fn RE5_ManualExportMergeLoadedItems loadedItems targetActionId =
	(
		local merged = false
		if loadedItems == undefined or loadedItems.count < 1 do return false
		for loadedIndex = 1 to loadedItems.count do
		(
			local loadedItem = loadedItems[loadedIndex]
			local found = false
			if loadedItem != undefined and loadedItem.count >= 6 do
			(
				loadedItem[6] = targetActionId
				for itemIndex = 1 to RE5ManualExportActionCandidates.count while found == false do
				(
					if RE5ManualExportActionCandidates[itemIndex] != undefined and RE5ManualExportActionCandidates[itemIndex].count >= 6 and RE5ManualExportActionCandidates[itemIndex][2] == loadedItem[2] then
					(
						RE5ManualExportActionCandidates[itemIndex] = loadedItem
						found = true
						merged = true
					)
				)
				if found == false do
				(
					append RE5ManualExportActionCandidates loadedItem
					merged = true
				)
			)
		)
		if RE5ManualExportActionCandidates.count > 1 do qsort RE5ManualExportActionCandidates RE5_ManualExportActionSort
		if merged == true do RE5_ManualExportRefreshLists()
		merged
	)

	on RE5ManualExportActionDialog open do
	(
		RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionNoTargetId())
		RE5_ManualExportApplyLanguage()
		RE5_ManualExportRefreshLists()
	)

	fn RE5_ManualExportReadCurrentSelectionIntoLane targetActionId =
	(
		local loadedItems = RE5_BuildManualExportActionCandidates RE5ManualExportActionMeshCount
		RE5_ManualExportSetLoadTargetAction targetActionId
		if loadedItems != undefined and loadedItems.count > 0 then
		(
			RE5_ManualExportMergeLoadedItems loadedItems targetActionId
		)
		else
		(
			messageBox (RE5_UIStr "当前选择里没有可识别的 Mesh_* 节点可加入此栏。" "Current selection does not contain any valid Mesh_* nodes for this lane.") title:(RE5_UIStr "没有可读取的 MESH" "No Loadable Mesh")
		)
	)

	fn RE5_ManualExportSelectAllInLane targetActionId sourceList =
	(
		RE5_ManualExportSetLoadTargetAction targetActionId
		RE5_ManualExportSelectLaneAll sourceList
	)

	fn RE5_ManualExportClearLaneWithTarget targetActionId clearModified:false =
	(
		RE5_ManualExportSetLoadTargetAction targetActionId
		if clearModified == true then
			RE5_ManualExportClearModifiedSelection()
		else
			RE5_ManualExportClearLane targetActionId
	)

	on btnLoadForce pressed do
	(
		RE5_ManualExportReadCurrentSelectionIntoLane (RE5_GetExportActionForceLOD0Id())
	)

	on btnLoadDelete pressed do
	(
		RE5_ManualExportReadCurrentSelectionIntoLane (RE5_GetExportActionDeleteId())
	)

	on btnLoadModified pressed do
	(
		RE5_ManualExportReadCurrentSelectionIntoLane (RE5_GetExportActionModMeshId())
	)

	on ddlForceMode selected idx do
	(
		local safeIdx = idx
		if idx == 3 do safeIdx = RE5_GetManualHeaderOnlyModeDisplayModeId()
		RE5ManualExportHeaderOnlyMode = RE5_GetSafeManualHeaderOnlyMode safeIdx
	)

	on mlbForce selected idx do
	(
		RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionForceLOD0Id())
	)

	on mlbDelete selected idx do
	(
		RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionDeleteId())
	)

	on mlbModified selected idx do
	(
		RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionModMeshId())
	)

	on btnTipForce pressed do
	(
		RE5_ManualExportShowUnifiedTips()
	)

	on btnTipDelete pressed do
	(
		RE5_ManualExportShowUnifiedTips()
	)

	on btnTipModified pressed do
	(
		RE5_ManualExportShowUnifiedTips()
	)

	on btnMoveToForce pressed do
	(
		RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionForceLOD0Id())
		RE5_ManualExportMoveSelections #(mlbModified, mlbDelete) (RE5_GetExportActionForceLOD0Id())
	)

	on btnMoveToDelete pressed do
	(
		RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionDeleteId())
		RE5_ManualExportMoveSelections #(mlbModified, mlbForce) (RE5_GetExportActionDeleteId())
	)

	on btnMoveToModified pressed do
	(
		RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionModMeshId())
		RE5_ManualExportMoveSelections #(mlbForce, mlbDelete) (RE5_GetExportActionModMeshId())
	)

	on btnSelectAllForce pressed do
	(
		RE5_ManualExportSelectAllInLane (RE5_GetExportActionForceLOD0Id()) mlbForce
	)

	on btnClearForce pressed do
	(
		RE5_ManualExportClearLaneWithTarget (RE5_GetExportActionForceLOD0Id())
	)

	on btnSelectAllDelete pressed do
	(
		RE5_ManualExportSelectAllInLane (RE5_GetExportActionDeleteId()) mlbDelete
	)

	on btnClearDelete pressed do
	(
		RE5_ManualExportClearLaneWithTarget (RE5_GetExportActionDeleteId())
	)

	on btnSelectAllModified pressed do
	(
		RE5_ManualExportSelectAllInLane (RE5_GetExportActionModMeshId()) mlbModified
	)

	on btnClearModified pressed do
	(
		RE5_ManualExportClearLaneWithTarget (RE5_GetExportActionModMeshId()) clearModified:true
	)

	on btnOk pressed do
	(
		local hasCandidates = (RE5ManualExportActionCandidates != undefined and RE5ManualExportActionCandidates.count > 0)
		local validationInfo = RE5_ValidateManualExportActionCandidates RE5ManualExportActionCandidates
		local modifiedNoSkinItems = RE5_FindManualModifiedNoSkinCandidates RE5ManualExportActionCandidates
		local noSkinDialogResult = #back
		if hasCandidates != true then
		(
			messageBox (RE5_UIGetManualExportEmptyWarningText()) title:(RE5_UIGetManualExportEmptyWarningTitle())
		)
		else if validationInfo != undefined and validationInfo.count >= 2 and validationInfo[1] != true then
		(
			messageBox (RE5_UIBuildManualExportConflictWarning validationInfo[2]) title:(RE5_UIGetManualExportConflictWarningTitle())
		)
		else if modifiedNoSkinItems != undefined and modifiedNoSkinItems.count > 0 then
		(
			RE5_ReenableManualExportGuideAutoShow()
			noSkinDialogResult = RE5_ShowManualExportNoSkinDialog modifiedNoSkinItems
			if noSkinDialogResult == #force then
			(
				RE5_ManualExportMoveActionItemsToLane modifiedNoSkinItems (RE5_GetExportActionForceLOD0Id())
				RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionForceLOD0Id())
			)
			else if noSkinDialogResult == #delete then
			(
				RE5_ManualExportMoveActionItemsToLane modifiedNoSkinItems (RE5_GetExportActionDeleteId())
				RE5_ManualExportSetLoadTargetAction (RE5_GetExportActionDeleteId())
			)
			else
			(
				RE5_ReenableManualExportGuideAutoShow()
			)
		)
		else if RE5_GetSafeManualHeaderOnlyMode RE5ManualExportHeaderOnlyMode == RE5_GetManualHeaderOnlyModeGroupId() then
		(
			messageBox (RE5_UIGetManualExportHeaderOnlyUnsafeText()) title:(RE5_UIGetManualExportHeaderOnlyUnsafeTitle())
			try (ddlForceMode.selection = RE5_GetManualHeaderOnlyDropdownSelection (RE5_GetManualHeaderOnlyModeLod0Id())) catch()
			RE5ManualExportHeaderOnlyMode = RE5_GetManualHeaderOnlyModeLod0Id()
		)
		else
		(
			RE5ManualExportActionResult = #ok
			destroyDialog RE5ManualExportActionDialog
		)
	)

	on btnSkip pressed do
	(
		RE5ManualExportActionResult = #skip
		destroyDialog RE5ManualExportActionDialog
	)

	on RE5ManualExportActionDialog close do
	(
		if RE5ManualExportActionResult == undefined or RE5ManualExportActionResult == #pending do RE5ManualExportActionResult = #cancel
	)
)

fn RE5_ShowManualExportActionDialog meshCount =
(
	local dialogOpen = false
	local guideResult = #ok
	RE5ManualExportActionMeshCount = meshCount
	RE5ManualExportActionCandidates = #()
	RE5ManualExportActionResult = #pending
	if RE5ExportEnableManualMeshActionDialog != true do return #skip
	guideResult = RE5_ShowManualExportGuideDialog()
	if guideResult != #ok and guideResult != #skip do return #cancel
	try(destroyDialog RE5ManualExportActionDialog)catch()
	createDialog RE5ManualExportActionDialog 580 500
	dialogOpen = true
	while dialogOpen == true and RE5ManualExportActionResult == #pending do
	(
		try (dialogOpen = RE5ManualExportActionDialog.isDisplayed) catch(dialogOpen = false)
		RE5_ProcessUI()
	)
	if RE5ManualExportActionResult == #pending do RE5ManualExportActionResult = #cancel
	RE5ManualExportActionResult
)

try(destroydialog Re5ModTool)catch()
rollout Re5ModTool "RE5 Mod Script v0.33a"
(
	button ImportButton "ImportMod" pos:[106,82] width:182 height:34
	button ExportButton "ExportToMod" pos:[106,126] width:182 height:34
	progressBar pbMain "" pos:[124,18] width:176 height:10 color:(color 70 150 230)
	label lblStatus "Ready" pos:[124,34] width:176 height:18
	groupBox grp3 "Mesh Rename" pos:[74,174] width:244 height:192
	label lblValue "Value" pos:[92,204] width:42 height:18
	editText edt4 "" pos:[200,200] width:96 height:24
	label lblReplace "Replace" pos:[92,242] width:52 height:18
	radioButtons rdo2 "" pos:[92,264] width:186 height:92 labels:#("LOD", "MAT", "Group", "Display") columns:1 default:1
	button btnLangCN "中" pos:[118,372] width:30 height:22
	button btnLangEN "EN" pos:[156,372] width:38 height:22
	button btn7 "Rename Selected" pos:[74,382] width:244 height:34

	fn RE5_ApplyLanguage =
	(
		if RE5_IsChineseUI() == true then
		(
			try (Re5ModTool.title = "RE5 MOD 脚本 v0.33a") catch()
			try (ImportButton.text = RE5_UIGetImportButtonText()) catch()
			try (ExportButton.text = RE5_UIGetExportButtonText()) catch()
			try (grp3.text = RE5_UIGetGroupTitleText()) catch()
			try (lblValue.text = RE5_UIGetValueLabelText()) catch()
			try (lblReplace.text = RE5_UIGetReplaceTitleText()) catch()
			try (rdo2.text = "") catch()
			try (rdo2.labels = RE5_UIGetReplaceLabels()) catch()
			try (btn7.text = RE5_UIGetRenameButtonText()) catch()
			try (btnLangCN.text = "中") catch()
			try (btnLangEN.text = "EN") catch()
			try (btnLangCN.enabled = false) catch()
			try (btnLangEN.enabled = true) catch()
			if lblStatus.text == "" or lblStatus.text == "Ready" do try (lblStatus.text = "就绪") catch()
		)
		else
		(
			try (Re5ModTool.title = "RE5 Mod Script v0.33a") catch()
			try (ImportButton.text = RE5_UIGetImportButtonText()) catch()
			try (ExportButton.text = RE5_UIGetExportButtonText()) catch()
			try (grp3.text = RE5_UIGetGroupTitleText()) catch()
			try (lblValue.text = RE5_UIGetValueLabelText()) catch()
			try (lblReplace.text = RE5_UIGetReplaceTitleText()) catch()
			try (rdo2.text = "") catch()
			try (rdo2.labels = RE5_UIGetReplaceLabels()) catch()
			try (btn7.text = RE5_UIGetRenameButtonText()) catch()
			try (btnLangCN.text = "中") catch()
			try (btnLangEN.text = "EN") catch()
			try (btnLangCN.enabled = true) catch()
			try (btnLangEN.enabled = false) catch()
			if lblStatus.text == "" or lblStatus.text == "就绪" do try (lblStatus.text = "Ready") catch()
		)
		try (RE5_UIApplyCurrentLayout()) catch()
		try (RE5_UIApplyDialogStateSize()) catch()
		true
	)

	on Re5ModTool open do
	(
		RE5_InitRuntimeProfile()
		RE5_ResetProgressState()
		RE5_ApplyLanguage()
		RE5_SetProgress 0 (RE5_UIStr "就绪" "Ready")
	)

	on btnLangCN pressed do
	(
		if RE5_IsChineseUI() != true do
		(
			RE5_SetUILanguage "CN" manual:true
			RE5_ApplyLanguage()
			RE5_SetProgress pbMain.value lblStatus.text
		)
	)

	on btnLangEN pressed do
	(
		if RE5_IsChineseUI() == true do
		(
			RE5_SetUILanguage "EN" manual:true
			RE5_ApplyLanguage()
			RE5_SetProgress pbMain.value lblStatus.text
		)
	)

	on ImportButton pressed do 
	(
		local importBatchStarted = false
		local importSucceeded = false
		RE5_InitRuntimeProfile()
		RE5_ResetProgressState()
		RE5_SetProgress 0 (RE5_UIStr "选择 MOD" "Choose MOD")
		clearlistener()
		fsource = GetOpenFileName \
		caption:(RE5_UIStr "选择 *.mod 文件" "Select *.mod File") \
		types: "RE5 Model(*.mod)|*.mod|All files (*.*)|*.*|"
		
		if fsource != undefined then
		(
			RE5_BeginImportBatchOp()
			importBatchStarted = true
			try
			(
				RE5_SetProgress 4 (RE5_UIStr "打开源文件" "Open source")
				
				f = fopen fsource "rb"
				if f == undefined do throw (RE5_UIStr "无法打开 MOD 文件。" "Failed to open MOD file.")
				--"MOD"
				Type = ReadFixedString f 4
				if Type != "MOD" do 
				(
					fclose f
					f = undefined
					throw (RE5_UIStr "这不是 MOD 文件。" "It is not Mod file")
				)
				mod_ver = readshort f #unsigned
			
			
			
			hdr = ReadHeader f 
			print hdr
			bCount = hdr.BoneCount
			RE5_SetProgress 8 (RE5_UIStr "读取头信息" "Read header")
			
			Local MeshScale = [1.0,1.0,1.0]
			--Bounding Sphere & Box
			fn GetBound bstream = ([(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream)])
			BoundingSphere = GetBound f ;BoundingBoxMin = GetBound f ;BoundingBoxMax = GetBound f 
			BoundSphere = Sphere radius: BoundingSphere[4]
			BoundSphere.pos = [BoundingSphere[1],BoundingSphere[2],BoundingSphere[3]]
			BoundSphere.name = "BoundSphere"
			BoundBoxMin = Point Size:10.0
			BoundBoxMin.name = "BoundBoxMin"
			BoundBoxMin.pos = [BoundingBoxMin[1],BoundingBoxMin[2],BoundingBoxMin[3]] 
			BoundBoxMax = Point Size:10.0
			BoundBoxMax.name = "BoundBoxMax"
			BoundBoxMax.pos = [BoundingBoxMax[1],BoundingBoxMax[2],BoundingBoxMax[3]]
			freeze BoundSphere ;Hide BoundSphere ;freeze BoundBoxMin ;Hide BoundBoxMin ;freeze BoundBoxMax ;Hide BoundBoxMax
			-- ?? 
			fseek f 16 #seek_cur
			-- unknow 
			-- if mod_ver==0x00D2 do (fseek f 4 #seek_cur)
			-- bone start at offset 0xb0
		    fseek f 32 #seek_cur

            if bCount > 0 then
            (
                RE5_SetProgress 14 (RE5_UIStr "读取骨骼" "Read bones")
                -- jump to bone section
                fseek f hdr.ptr_Bone #seek_set
                
                print BoundingBoxMin
                print BoundingBoxMax
                
                --Bones
                BoneArray=#()			
                for i=1 to bCount do
                (
                    if i == 1 or i == bCount or (mod i 32) == 0 do RE5_SetProgress (14 + ((i as float / bCount) * 10.0)) (RE5_UIStr ("读取骨骼 " + (i as string) + "/" + (bCount as string)) ("Read bones " + (i as string) + "/" + (bCount as string)))
                    bInfo = ReadBoneInfo f
                    cBone = Dummy size:1.0
                    cBone.showLinks = true
                    cBone.showLinksOnly = true
                    if bInfo.Parent == 255 then
                          cBone.name = "b_" + (0)as string +"_"+ i as string	
                    else
                          cBone.name = "b_" + (bInfo.Parent+1)as string +"_"+ i as string
                        
                    Append BoneArray cBone	
                )
                            
                fn ReadMatrix bstream =
                (
                    local Mat = Matrix3 1
                    Mat.row1 = [(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream)]
                    Mat.row2 = [(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream)]
                    Mat.row3 = [(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream),(ReadFloat bstream)]
                    tYZ = [-(ReadFloat bstream),-(ReadFloat bstream),(ReadFloat bstream)]	 
                    Mat.row4 = [tYZ.x,tYZ.z,tYZ.y,(ReadFloat bstream)]	
                    Mat
                )
                for i=1 to bCount do	--Local ??
                (
                    BoneLocalMatrix = ReadMatrix f				
                )
                for i=1 to bCount do	--World
                (
                    BoneWorldMatrix = ReadMatrix f							
                    BoneArray[i].transform = BoneWorldMatrix
                )
                MeshScale = BoneArray[1].scale
                for i=2 to bCount do	--World
                (
                    BoneArray[i].scale = [1.0,1.0,1.0]
                    ParentID = filterString BoneArray[i].name "_"
                    pID = execute ParentID[2]
                    if pID != 0 then BoneArray[i].Parent = BoneArray[pID]	
                )
                
                fseek f 256 #seek_cur     -- skip bone table
                                    
                -- read bone group
                bmc = hdr.BoneMapCount
                BoneGroup_array = #()
                BoneGroup_array.count = bmc
                real_bg_cnt = bmc
                read_bone = true
                local bg
                i = 1
                while  i  <= bmc do
                (

                    bg = ReadBoneGroup f
                     format " total  % bmc %  cnt % \n" bmc i bg.boneCount
                     BoneGroup_array[i]=bg
                     if bg.boneCount > 32  do
                     (

                         no_bg = ceil ((bg.boneCount-32) /36.0)  -- round up to next 32 bones
        
                         left_to_read = no_bg * (4+32) - ( bg.boneCount - 32 )
                                         format "no_bg % left to read %\n" no_bg left_to_read
                         fseek f left_to_read #seek_cur
                         for j = 1 to no_bg do
                         (
                             i += 1
                            local new_bg = BoneGroup ()
                            
                            new_bg.boneCount = 1
                            new_bg.boneId = #(0)
                            BoneGroup_array[i] = new_bg
                             format " bmc %  cnt % \n" i new_bg.boneCount
                         )
                     )
                     
                     i += 1
                )		
					--print BoneGroup_array[i].boneCount
					--format "%\n"  BoneGroup_array[i].boneId			
                    --unknow ??
            )		
            
            fn ReadTex fstream = 
            (
                local i
                local str =""
                i = 1
                ch = ReadByte fstream
                while (ch > 0 and i < 64) do
                (
                    str+= bit.intAsChar ch 
                    ch = ReadByte fstream
                    i+=1
                )
                while (i < 64) do
                (
                    ReadByte fstream
                    i+=1
                )
                str               
            )            
            
            --Texture info
            TexArray = #()
            TexArray.count = hdr.TextureCount            
            
            fseek f hdr.ptr_Texture #seek_Set
            for i = 1 to hdr.TextureCount do
            (
               TexArray[i]=ReadTex f
            )
                        
			--MatID~  MatPtr = hdr.ptr_MatID
            
            ptr_Mat = hdr.ptr_Texture + ( 64 * hdr.TextureCount)
			fseek f ptr_Mat #seek_Set

			--MatList = Dummy size:10.0
			--MatList.name = "MaterialList"            
            MatCount = hdr.MatCount
            MatArray = #()
            MatArray.count = MatCount
            
            -- Material texture slot 1-8, mod tool currently supports only two unique UV channel. 
            -- 1,2,3 , BM, NM ,MM   (color, normal, specular , uv channel 1)
            -- 4,5   , LM, LM       (light map , uv channel 2)
            -- 6     , AM           (audio map? , uv channel 1)
            -- 7     , CM           (cube map , does not need uv)
            ---8     , unknown
            for i=1 to MatCount do
            (
                MatArray[i] = ReadMatInfo f
                --newMat = Dummy size:10.0
                --newMat.name = "Mat_"+((i-1)as string)
                format "Material %:\n" (i-1)
                for j=1 to 8 do
                (
                    index = MatArray[i].Tex[j]
					if (index >0) do
						format "    Texture: %\n" TexArray[index]
                    --if  index > 0 do
                    --(
                       --newTex=Dummy size:10.0
                       --newTex.name=TexArray[index]
                       --newTex.parent = newMat
                    --)
                )                
            )
                    
			--Mesh Info
			fseek f hdr.ptr_Mesh #seek_Set

			--mesh info
			mc = hdr.MeshCount
			MeshInfo_array = #()
			MeshInfo_array.count = mc
			for i=1 to mc do	
			(	
				mhdr = ReadMeshHeader f	
				MeshInfo_array[i] = #(mhdr.vertCount,mhdr.vertStride,mhdr.vertStart,mhdr.vertBase,mhdr.faceStart,mhdr.faceCount,mhdr.faceBase,mhdr.lodLevel,mhdr.vertFlag,mhdr.matId,mhdr.bonemapindex,mhdr.unk07,mhdr.faceBase)
                    --MatArray[mhdr.matId+1])
				--fvft = bit.intashex mhdr.fvfInfo
				--print fvft					
				--print mhdr.bonemapindex
			)
		
			-- vertex
			MeshVertex_array = #()
			MeshVertex_array.count = mc
			MeshNorm_array = #()
			MeshNorm_array.count = mc			
			MeshUV_array = #()
			MeshUV_array.count = mc
            
   			MeshUV2_array = #()    -- light map  has its own UV map
			MeshUV2_array.count = mc
			MeshColor_array = #()
			MeshColor_array.count = mc
			MeshBoneID_array = #()
			MeshBoneID_array.count = mc
			MeshBoneWeight_array = #()
			MeshBoneWeight_array.count = mc
			MeshBoneLimit = #()
			MeshBoneLimit.count = mc
				
			fn ReadVertexPos bstream =
			(
				local vp = [0,0,0]
				vp.x = (readshort bstream)
				vp.y = (readshort bstream)
				vp.z = (readshort bstream)
				vp
			)				
			fn ReadBoneID bstream = [(readByte bstream #unsigned),(readByte bstream #unsigned),(readByte bstream #unsigned),(readByte bstream #unsigned)] 
			fn ReadBoneWeight bstream = [(readByte bstream #unsigned),(readByte bstream #unsigned),(readByte bstream #unsigned),(readByte bstream #unsigned)] 	
			fn w_comp a b = (
			if a[1] > b[1] then 1
			else if a[1] < b[1] then -1
			else 0
			)
			
			for i=1 to mc do	 
			(
				if i == 1 or i == mc or (mod i 16) == 0 do RE5_SetProgress (26 + ((i as float / mc) * 18.0)) (RE5_UIStr ("读取顶点 " + (i as string) + "/" + (mc as string)) ("Read vertices " + (i as string) + "/" + (mc as string)))
				--�ƶ��������ַ
				fseek f (hdr.ptr_vertex + MeshInfo_array[i][4]) #seek_Set
				--fseek f (MeshInfo_array[i][2]*(MeshInfo_array[i][3])) #seek_cur
				fseek f (MeshInfo_array[i][2]*(MeshInfo_array[i][3]+MeshInfo_array[i][13])) #seek_cur
				
				vc = MeshInfo_array[i][1]
				VertexPos_array = #()		
				VertexPos_array.count = vc
				UV_array = #()
				UV_array.count = vc
   				UV2_array = #()
				UV2_array.count = vc
				Color_array = #()
				Color_array.count = vc

				Norm_array = #()
				Norm_array.count = vc
                
                if (bCount == 0) then    -- mod file contains no bone, assume this is a stage mesh
                (
                    hasNorMap = MatArray[MeshInfo_array[i][10]+1].hasNorMap
                    hasLgtMap = MatArray[MeshInfo_array[i][10]+1].hasLgtMap
					(for c=1 to vc do ----withskin x y z w  b1 b2 b3 b4 w1 w2 w3 w4 nx ny nz nw tx ty tw tz  u1 v1 u2 v2 
					(
						v = [ReadFloat f, ReadFloat f, ReadFloat f]			
						--if i==7 do format "v% pos %\n" c v
						
						VertexPos_array[c] =[ v[1],-v[3], v[2]]

						
						
						--if i == 36 do format "% % % % % % % %\n"  rb1 rb2 rb3 rb4 w1 w2 w3 w4
						--fseek f 8 #seek_cur    -- skip normal, tangent
						vNorm = ReadBoneID f		
						vTan = ReadBoneID f
						--if i ==7 do format "v% nor %\n" c vNorm				
						--if i ==7 do format "v% tan %\n" c vTan
							
						vNorm -= 127.0
						vNorm /= 127.0
						Norm_array[c] = vNorm
						
						-- first UV
						u1 = ReadShort f
						v1 = ReadShort f
						--if i == 13 do format "v % uv % %\n" c u1 v1
	
						vUV = [(ReadFloat16 u1),(ReadFloat16 v1)*-1.0 + 1.0,0.0]
                        --vUV = [(ReadFloat16 f),(ReadFloat16 f)*-1.0 + 1.0,0.0]
                        UV_array[c]=vUV
                        if hasNorMap == true then
                        (
                            fseek f 4 #seek_cur   -- skip normal map UV, assume same as first  UV
                        )
						
						if hasLgtMap == true then
						(
								u1 = ReadShort f
								v1 = ReadShort f
								UV2_array[c]=[(ReadFloat16 u1),(ReadFloat16 v1)*-1.0 + 1.0,0.0]
                                --format " mesh % uv1 % uv2 %\n" i UV_array[c] UV2_array[c] 
								if hasNorMap == false do
										fseek f 4 #seek_cur
						)
						else
						(
								if hasNorMap == false then 
									fseek f 4 #seek_cur
								-- read vertex color
								r = ReadByte f #unsigned
								g = ReadByte f #unsigned
								b = ReadByte f #unsigned
								a = ReadByte f #unsigned
								Color_array[c] = color r g b a
                                --format "mesh % color %\n" i Color_array[c]
						)
						
                            
						
					)
					MeshBoneLimit[i] = 4 )
                    
                    if hasLgtMap == true do 
                        MeshUV2_array[i] = UV2_array
                    MeshNorm_array[i] = Norm_array 
					MeshColor_array[i] = Color_array
                )
                else     -- mesh use bones
                (
				BoneID_array = #()
				BoneID_array.count = vc
				BoneWeight_array = #()
				BoneWeight_array.count = vc
				
				--format " m % base % vsize % vstart % \n" i MeshInfo_array[i][4] MeshInfo_array[i][2] MeshInfo_array[i][3]
				--print (bit.intashex MeshInfo_array[i][9])
				
				-- ���ڳ�������Ч�Ķ�������û��ȫ���༭	
				local b1=0
				local b2=0
				local b3=0
				local b4=0
				local rb1=0
				local rb2=0
				local rb3=0
				local rb4=0
				local w1=0.0
				local w2=0.0
				local w3=0.0
				local w4=0.0
				local wa = 0.0
				case  MeshInfo_array[i][9] of
				(   
					--(0x00) :
					default: (for c=1 to vc do ----withskin x y z w  b1 b2 b3 b4 w1 w2 w3 w4 nx ny nz nw tx ty tw tz  u1 v1 u2 v2 
					(
						v = ReadVertexPos f			
						--if i==7 do format "v% pos %\n" c v
						
						VertexPos_array[c] =[ v[1]/32767.0* (BoundingBoxMax[1]-BoundingBoxMin[1])+BoundingBoxMin[1],
						-(v[3]/32767.0* (BoundingBoxMax[3]-BoundingBoxMin[3])+BoundingBoxMin[3]),
						v[2]/32767.0* (BoundingBoxMax[2]-BoundingBoxMin[2])+BoundingBoxMin[2] ]

						fseek f 2 #seek_cur   --skip w
						b1 = readbyte f #unsigned
						b2 = readbyte f #unsigned
						b3 = readbyte f #unsigned
						b4 = readbyte f #unsigned
						w1 = (readbyte f #unsigned)
						w2 = (readbyte f #unsigned)
						w3 = (readbyte f #unsigned)
						w4 = (readbyte f #unsigned)
						
						if b1 == 255 do -- special check for fairytale sheva, this is a  weird vertex that have no bone id and weight
						(
							b1 = 0
							b2 = 0
							b3 = 0
							b4 = 0
							w1 = 255
							w2 = 0
							w3 = 0
							w4 = 0
						)
						-- if i == 47 do  format " v % % % % % % % % %\n" c b1 b2 b3 b4 w1 w2 w3 w4
						-- if i == 7 do format "v % bone [%] % % % % % % % %\n" c (MeshInfo_array[i][11]+1) b1 b2 b3 b4 w1 w2 w3 w4
						w1/=255.0
						w2/=255.0
						w3/=255.0
						w4/=255.0
						b1 += 1
						b2 += 1
						b3 += 1
						b4 += 1
						-- translate bone index to  bone id
						bg_id = MeshInfo_array[i][11]+1;
						
						if w1 > 0 then rb1 = BoneGroup_array[bg_id].boneId[b1] + 1
							else rb1 = 1
						if w2 > 0 then rb2 = BoneGroup_array[bg_id].boneId[b2] + 1
							else rb2 = 1
						if w3 > 0 then rb3 = BoneGroup_array[bg_id].boneId[b3] + 1
							else rb3 = 1
						if w4 > 0 then rb4 = BoneGroup_array[bg_id].boneId[b4] + 1
							else rb4 = 1
						
						
						--if i == 36 do format "% % % % % % % %\n"  rb1 rb2 rb3 rb4 w1 w2 w3 w4
						--fseek f 8 #seek_cur    -- skip normal, tangent
						vNorm = ReadBoneID f		
						vTan = ReadBoneID f
						--if i ==7 do format "v% nor %\n" c vNorm				
						--if i ==7 do format "v% tan %\n" c vTan
							
						vNorm -= 127.0
						vNorm /= 127.0
						--Norm_array[c] = vNorm
						
--						vUV = [(ReadFloat16 f),(ReadFloat16 f)*-1.0 + 1.0,0.0]
						u1 = ReadShort f
						v1 = ReadShort f
						--if i == 13 do format "v % uv % %\n" c u1 v1
	
						vUV = [(ReadFloat16 u1),(ReadFloat16 v1)*-1.0 + 1.0,0.0]
						
						fseek f 4 #seek_cur   -- skip second uv
						UV_array[c]=vUV
						BoneID_array[c] = #(rb1,rb2,rb3,rb4)
						BoneWeight_array[c] = #(w1,w2,w3,w4)
					)
					MeshBoneLimit[i] = 4 )
				    (0x08): (for c=1 to vc do ----withskin x y z w  b1 b2 b3 b4 b5 b6 b7 b8 w1 w2 w3 w4 w5 w6 w7 w8 nx ny nz nw  u1 v1
					(
						v = ReadVertexPos f						
						VertexPos_array[c] =[ v[1]/32767.0* (BoundingBoxMax[1]-BoundingBoxMin[1])+BoundingBoxMin[1],
						-(v[3]/32767.0* (BoundingBoxMax[3]-BoundingBoxMin[3])+BoundingBoxMin[3]),
						v[2]/32767.0* (BoundingBoxMax[2]-BoundingBoxMin[2])+BoundingBoxMin[2] ]
						b=#()
						b.count =8
						w=#()
						w.count =8
						fseek f 2 #seek_cur     -- skip w
						b[1] = readbyte f #unsigned
						b[2] = readbyte f #unsigned
						b[3] = readbyte f #unsigned
						b[4] = readbyte f #unsigned
						b[5] = readbyte f #unsigned
						b[6] = readbyte f #unsigned
						b[7] = readbyte f #unsigned
						b[8] = readbyte f #unsigned
						--fseek f 4 #seek_cur
						w1 = (readbyte f #unsigned)/255.0
						w2 = (readbyte f #unsigned)/255.0
						w3 = (readbyte f #unsigned)/255.0
						w4 = (readbyte f #unsigned)/255.0
						w5 = (readbyte f #unsigned)/255.0
						w6 = (readbyte f #unsigned)/255.0
						w7 = (readbyte f #unsigned)/255.0
						w8 = (readbyte f #unsigned)/255.0
						w_array = #( #(w1,1) , #(w2,2) , #(w3,3) , #(w4,4) , #(w5,5),  #(w6,6), #(w7,7), #(w8,8))
							
						-- sort bone by weight, only use top 4 bones. 
						qsort w_array w_comp
						b1=b[w_array[8][2]]
						b2=b[w_array[7][2]]
						b3=b[w_array[6][2]]
						b4=b[w_array[5][2]]
						w1 = w_array[8][1]
						w2 = w_array[7][1]
						w3 = w_array[6][1]
						w4 = w_array[5][1]
						--if i == 29 do format " v % % % % % % % % %\n" c b1 b2 b3 b4 w1 w2 w3 w4							
							
						wt = w1 + w2 + w3 +w4     -- re distribute weight to first 4 bones
						w1/=wt;
						w2/=wt;
						w3/=wt;
						w4/=wt;
						--if i == 29 do format " v % % % % % % % % %\n" c b1 b2 b3 b4 w1 w2 w3 w4							
							
						--if true do format "v % bone [%] % % % % % % % %\n" c (MeshInfo_array[i][11]+1) b1 b2 b3 b4 w1 w2 w3 w4
						b1 += 1
						b2 += 1
						b3 += 1 
						b4 += 1
						-- translate bone index to  bone id
						rb1=rb2=rb3=rb4=1  --  3dsmax bug. if only one bone has weight, the other 3 cannot use the same bone id. otherwise vertex will not move with bone.
						if w1 > 0.0 do rb1 = BoneGroup_array[MeshInfo_array[i][11]+1].boneId[b1] + 1 
						if w2 > 0.0 do rb2 = BoneGroup_array[MeshInfo_array[i][11]+1].boneId[b2] + 1 
						if w3 > 0.0 do rb3 = BoneGroup_array[MeshInfo_array[i][11]+1].boneId[b3] + 1 
						if w4 > 0.0 do rb4 = BoneGroup_array[MeshInfo_array[i][11]+1].boneId[b4] + 1 
						
						--if i == 29 do format " v % % % % % % % % % [% % % %]\n" c b1 b2 b3 b4 w1 w2 w3 w4 rb1 rb2 rb3 rb4
						fseek f 4 #seek_cur   -- skip  normal
						
						u1 = ReadShort f
						v1 = ReadShort f
						--if i == 13 do format "v % uv % %\n" c u1 v1
	
						vUV = [(ReadFloat16 u1),(ReadFloat16 v1)*-1.0 + 1.0,0.0]
						--fseek f 4 #seek_cur
						UV_array[c]=vUV
						BoneID_array[c] = #(rb1,rb2,rb3,rb4)
						BoneWeight_array[c] = #(w1,w2,w3,w4)
					)
					MeshBoneLimit[i] = 4)
				)		
   				MeshBoneID_array[i] = BoneID_array  
				MeshBoneWeight_array[i] = BoneWeight_array

				)
				MeshVertex_array[i] = VertexPos_array	
				--MeshNorm_array[i] = Norm_array 
				MeshUV_array[i] = UV_array
					
			)
			
			--build mesh
			fseek f hdr.ptr_triangle #seek_Set
			MeshFace_array = #()
			MeshFace_array.count = mc

			for i=1 to mc do	 
			(
				if i == 1 or i == mc or (mod i 16) == 0 do RE5_SetProgress (46 + ((i as float / mc) * 12.0)) (RE5_UIStr ("读取面 " + (i as string) + "/" + (mc as string)) ("Read faces " + (i as string) + "/" + (mc as string)))
				Face_array = #()
				rfc = 0
				fc = MeshInfo_array[i][6] 	
				--format " mesh % vc % fc %\n"  i MeshInfo_array[i][1] fc 
				vc = MeshInfo_array[i][1]				
				vstart = MeshInfo_array[i][3]
                vbase =  vstart - 1
				v_max = vstart + vc - 1
				local rawVertFlag = MeshInfo_array[i][9]
				local isTriangleList = RE5_IsTriangleListFlag rawVertFlag
				fseek f hdr.ptr_triangle #seek_Set
				fseek f (MeshInfo_array[i][5]*2) #seek_cur
				if isTriangleList == true then
				(
					local triFaceCount = fc / 3
					local notdone = true
					Face_array.count = triFaceCount
					for c = 1 to triFaceCount while notdone do
					(
						f1 = readShort f #unsigned
						f2 = readShort f #unsigned
						f3 = readShort f #unsigned
						if f1 == undefined or f2 == undefined or f3 == undefined then
						(
							notdone = false
						)
						else if f1 > v_max or f2 > v_max or f3 > v_max or f1 < vstart or f2 < vstart or f3 < vstart then
						(
							notdone = false
						)
						else
						(
							fi = [f1,f2,f3]
							if f1 != f2 and f2 != f3 and f3 != f1 then
							(
								rfc += 1
								Face_array[rfc] = fi - [vbase,vbase,vbase]
							)
						)
					)
				)
				else
				(
					Face_array.count = fc
					f1 = readShort f #unsigned
					f2 = readShort f #unsigned
					notdone = true
	               
					for c=1 to fc while notdone  do
					(
						f3 = readShort f #unsigned
						--if f3 < 0 do f3 = f2
						if  f3 == undefind or f3 > v_max or f3 < vstart then 
						(
							notdone = false
						)
						else
						(
							if (mod c 2 != 0)  then
							( fi =[ f1, f2, f3] )
							else
							( fi = [ f1, f3, f2] )
	                       
							-- discard degenerated triangles
							if  f1 == f2 or f2 == f3 or f3 == f1 then
							(
								-- skip it
							)
							else
							( 
								rfc +=1	
								Face_array[rfc] = fi - [vbase,vbase,vbase]
								--if i == 47 do format " % " fi
							)		
							f1=f2
							f2=f3
						)
					)
                    --if i == 70 do
                    --(                        format " mesh % % \n" c fi
                    --   if c > 12 do notdone =false
                    --)                

				)
				Face_array.count  = rfc
				MeshFace_array[i] = Face_array
			)

			--build mesh 
			--Lod ����
			Lod1 = Dummy size:10.0
			Lod1.name = "LodGroup_1"
			
			Lod2 = Dummy size:10.0
			Lod2.name = "LodGroup_2"
			
			Lod3 = Dummy size:10.0
			Lod3.name = "LodGroup_3"
			
			Lod255 = Dummy size:10.0
			Lod255.name = "LodGroup_255"
			
			Lod252 = Dummy size:10.0
			Lod252.name = "LodGroup_252"
			
			OtherMesh = Dummy size:10.0
			OtherMesh.name = "OtherMesh"
			ImportedMeshNodes = #()
			ImportedMeshNodes.count = mc
			DeferredSkinMeshIndices = #()
			
			--global RE5_Mesh = #()    -- for exporting matid and lod
			--RE5_Mesh.count = mc
			with redraw off
			(
				for i=1 to mc do	 
				(
					if i == 1 or i == mc or (mod i 8) == 0 do RE5_SetProgress (60 + ((i as float / mc) * 32.0)) (RE5_UIStr ("创建场景 Mesh " + (i as string) + "/" + (mc as string)) ("Build scene meshes " + (i as string) + "/" + (mc as string)))
					--if i == 47 do format "m % f %\n" i MeshFace_array[i] 
					if RE5_CanBuildImportedSceneMesh MeshInfo_array[i] MeshVertex_array[i] MeshFace_array[i] MeshUV_array[i] != true then
					(
						local skipVertCount = 0
						local skipFaceCount = 0
						local skipUVCount = 0
						try (skipVertCount = MeshInfo_array[i][1] as integer) catch(skipVertCount = 0)
						try (skipFaceCount = MeshFace_array[i].count as integer) catch(skipFaceCount = 0)
						try (skipUVCount = MeshUV_array[i].count as integer) catch(skipUVCount = 0)
						ImportedMeshNodes[i] = undefined
						if RE5_ShouldUseExportVerboseDebug() do format "RE5 import skip empty mesh slot % vc:% faceCount:% uvCount:%\n" i skipVertCount skipFaceCount skipUVCount
						continue
					)
					new_mesh = mesh vertices:MeshVertex_array[i] faces:MeshFace_array[i] 
					new_mesh.name = 
					(
						"Mesh_"+ (paddstring 3 (i as string)) +"_"+ \
						(paddstring 2 ((bit.intashex MeshInfo_array[i][9]) as string)) +"_LODx"+ \
						MeshInfo_array[i][8] as string + "_MatIDx" + MeshInfo_array[i][10] as string + \
						"_Groupx" + MeshInfo_array[i][11] as string + "_DisplayModex" + \
						MeshInfo_array[i][12] as string
					)
					new_mesh.scale = MeshScale
					ImportedMeshNodes[i] = new_mesh
					
					--RE5_Mesh[i] = new_mesh
					
					vc = MeshInfo_array[i][1]
					--fc = MeshInfo_array[i][6] - 1
					fc = MeshFace_array[i].count
					
					--build UV
	                    
					setNumTVerts new_mesh vc			
	                --meshop.setNumMaps new_mesh 3 true
	                
					for c=1 to vc do
					(
						setTVert new_mesh c MeshUV_array[i][c]
	                    --meshop.setMapVert new_mesh 2 c MeshUV_array[i][c]
	                     
	                    
	                    --setNormal new_mesh c MeshNorm_array[i][c]
					)
	                if bCount == 0 then (
	                    for c=1 to vc do
	                    (                        
	                        --setNormal new_mesh c MeshNorm_array[i][c]
	                    )
						if 	MatArray[	MeshInfo_array[i][10]+1].hasLgtMap == false do
						(
							--setNumCPVVerts new_mesh vc true
	                        defaultVCFaces new_mesh
							for c=1 to vc do
							(                        
								setVertColor new_mesh c MeshColor_array[i][c]
							)					
						)
	                )
	                
					buildTVFaces new_mesh false	
					for f=1 to fc do
					(
						setTVFace new_mesh f MeshFace_array[i][f]                    
					)	

	                -- if light map exists, create UV channel 2 ( on top of channel 0,1 )
	                if bCount == 0 do (
	                hasLgtMap = MatArray[MeshInfo_array[i][10]+1].hasLgtMap
	                if  hasLgtMap == true do
	                (
	                    meshop.setNumMaps new_mesh 3 keep:true
	                    
	                    --meshop.setNumMapVerts new_mesh 2 vc false
	                    meshop.defaultMapFaces new_mesh 2
	                    for c=1 to vc do
	                    (                    
	                          meshop.setMapVert new_mesh 2 c MeshUV2_array[i][c]   
	                          --format " mesh % uv2 %\n" i MeshUV2_array[i][c]
	                    )
	                    --meshop.buildFaces new_mesh 2 false
	                    for f=1 to fc do
	                    (
	                        meshop.setMapFace new_mesh 2 f MeshFace_array[i][f]
	                    )	                     
	                )
	                )
					
					
					--Skin
					if bCount > 0 and MeshBoneID_array[i][1] != undefined then 
					(
						if MeshInfo_array[i][8] == 1 then new_mesh.Parent = Lod1
						if MeshInfo_array[i][8] == 2 then new_mesh.Parent = Lod2	
						if MeshInfo_array[i][8] == 3 then new_mesh.Parent = Lod3	
						if MeshInfo_array[i][8] == 255 then new_mesh.Parent = Lod255
						if MeshInfo_array[i][8] == 252 then new_mesh.Parent = Lod252	
						append DeferredSkinMeshIndices i
					)
					else						
					(
						new_mesh.Parent = OtherMesh													
					)
				)
			)			
			if bCount > 0 and DeferredSkinMeshIndices.count > 0 then
			(
				with redraw off
				(
					for skinPass = 1 to DeferredSkinMeshIndices.count do
					(
						local meshIndex = DeferredSkinMeshIndices[skinPass]
						if skinPass == 1 or skinPass == DeferredSkinMeshIndices.count or (mod skinPass 8) == 0 do RE5_SetProgress (92 + ((skinPass as float / DeferredSkinMeshIndices.count) * 8.0)) (RE5_UIStr ("应用蒙皮 " + (skinPass as string) + "/" + (DeferredSkinMeshIndices.count as string)) ("Apply skin " + (skinPass as string) + "/" + (DeferredSkinMeshIndices.count as string)))
						try
						(
							RE5_ApplyDeferredImportSkin ImportedMeshNodes[meshIndex] BoneArray MeshBoneLimit[meshIndex] MeshBoneID_array[meshIndex] MeshBoneWeight_array[meshIndex]
						)
						catch()
					)
				)
			)
				importSucceeded = true
			)
			catch
			(
				local importError = getCurrentException()
				if importError == undefined then importError = (RE5_UIStr "导入失败。" "Import failed.")
				RE5_SetProgress 0 (RE5_UIStr "导入失败" "Import failed")
				messageBox (importError as string)
			)
			if f != undefined do
			(
				try (fclose f) catch()
				f = undefined
			)
			if importBatchStarted == true do
			(
				RE5_EndImportBatchOp()
				try (completeRedraw()) catch()
			)
			if importSucceeded == true do RE5_SetProgress 100 (RE5_UIStr "导入完成" "Import complete")
		)
	) --import end
	
	on ExportButton pressed do 
	(
		local ManualExportActionMode = #skip
		local ManualExportActionMap = #()
		local ManualDeleteMeshFlags = #()
		RE5_InitRuntimeProfile()
		RE5_ResetProgressState()
		RE5_SetProgress 0 (RE5_UIStr "选择 MOD" "Choose MOD")
		clearlistener()
		fsource = GetOpenFileName \
		caption:(RE5_UIStr "选择 *.mod 文件" "Select *.mod File") \
		types: "RE5 Model(*.mod)|*.mod|All files (*.*)|*.*|"
		if fsource != undefined and selection.count!=0 then
		(
			RE5_SetProgress 4 (RE5_UIStr "打开源文件" "Open source")
			f = fopen fsource "rb"
			if f != undefined then
			(
				--��� .mod �ļ�					
				Type = ReadFixedString f 4
				if Type != "MOD" do 
				(
						messageBox (RE5_UIStr "这不是 MOD 文件。" "It is not Mod file")
						fclose f
				)
				
				--�������ļ�
				nf = fopen (fsource +".NewMOD") "wb"
				
				--�ļ�ͷ
				WriteString nf "MOD" --MOD
				fseek f 4 #seek_Set;mod_ver = readshort f #unsigned
				WriteShort nf mod_ver			--�汾
				BoneCount = readshort f 
				WriteShort nf BoneCount			--������Ŀ
				MeshCount = readshort f 
				ManualExportActionMode = RE5_ShowManualExportActionDialog MeshCount
				if ManualExportActionMode == #cancel then
				(
					try (fclose nf) catch()
					nf = undefined
					try (fclose f) catch()
					f = undefined
					try (if doesFileExist (fsource + ".NewMOD") do deleteFile (fsource + ".NewMOD")) catch()
					RE5_SetProgress 0 (RE5_UIStr "已取消导出" "Export cancelled")
					return false
				)
				else if ManualExportActionMode == #ok then
				(
					ManualExportActionMap = RE5_BuildManualExportActionMap MeshCount RE5ManualExportActionCandidates
					ManualDeleteMeshFlags = RE5_BuildManualDeleteMeshFlags MeshCount ManualExportActionMap
				)
				else
				(
					ManualExportActionMap.count = MeshCount
					ManualDeleteMeshFlags.count = MeshCount
					for manualMeshIndex = 1 to MeshCount do
					(
						ManualExportActionMap[manualMeshIndex] = RE5_GetExportActionModMeshId()
						ManualDeleteMeshFlags[manualMeshIndex] = false
					)
				)
				WriteShort nf MeshCount			--Mesh��Ŀ
				MatCount = readshort f 
				WriteShort nf MatCount			--������Ŀ
				OrgVertexCount = readlong f 
				WriteLong nf OrgVertexCount		--ԭʼ���嶥����Ŀ				
				OrgFaceCount = readlong f 
				WriteLong nf OrgFaceCount		--ԭʼ��������Ŀ
				OrgVertexIds = readlong f 
				WriteLong nf OrgVertexIds		--??
				OrgVertexSize = readlong f 
				WriteLong nf OrgVertexSize		--??
				OrgVertexSize2 = readlong f 
				WriteLong nf OrgVertexSize2			--padding , 2nd vertex stream	size			
				TextureCount = readlong f 
				WriteLong nf TextureCount		--������Ŀ
				GroupCount = readlong f 
				WriteLong nf GroupCount		--  some group  info
				BoneMapCount = readlong f 
				WriteLong nf BoneMapCount		--BoneMapCount, bone group	
				ptr_Bone = readlong f 
				WriteLong nf ptr_Bone			--ptr_Bone				
				ptr_Group = readlong f 
				WriteLong nf ptr_Group		--ptr Group array				
				ptr_Texture = readlong f 
				WriteLong nf ptr_Texture			--ptr_MatID	, texture offset
				ptr_Mesh = readlong f 
				WriteLong nf ptr_Mesh			--ptr_Mesh				
				ptr_vertex = readlong f 
				WriteLong nf ptr_vertex			--ptr_vertex	
				ptr_vertex2 = readlong f 
				WriteLong nf ptr_vertex2			--ptr_vertex2	
				OrgPtr_triangle = readlong f 
				WriteLong nf OrgPtr_triangle	--ԭʼFace ��ַ Ptr_triangle	
				padding = readlong f 
				WriteLong nf padding			--ԭʼ�ļ���С 
				OrgEndSize = readlong f 
				WriteLong nf OrgEndSize			--ԭʼ�ļ���С	
				
				--��Χ�� Bound
				ReadTempx = ReadFloat f 
				WriteFloat nf ReadTempx			--Բ X
				ReadTempy = ReadFloat f 
				WriteFloat nf ReadTempy			--Բ Y
				ReadTempz = ReadFloat f 
				WriteFloat nf ReadTempz			--Բ Z
				ReadTempw = ReadFloat f 
				WriteFloat nf ReadTempw			--Բ R
				
				fseek f 32 #seek_cur   -- skip min max bounding box
				
				BoundMin = $BoundBoxMin.pos		-- Bound box min
				Writefloat nf BoundMin.x
				Writefloat nf BoundMin.y
				Writefloat nf BoundMin.z
				Writefloat nf 0.0
				BoundMax = $BoundBoxMax.pos		-- Bound box max
				Writefloat nf BoundMax.x
				Writefloat nf BoundMax.y
				Writefloat nf BoundMax.z
				Writefloat nf 0.0		
				
				RE5_SetProgress 10 (RE5_UIStr "写入文件头" "Write header")
				
				if RE5_ShouldUseExportVerboseDebug() do format "sphere % % % %\n" ReadTempx ReadTempy ReadTempz ReadTempw
				--unknow
				
				ReadTemp = readlong f 				
				WriteLong nf ReadTemp	
				ReadTemp = readlong f 				
				WriteLong nf ReadTemp	
				ReadTemp = readlong f 	   -- 00 00 00 03			
				WriteLong nf ReadTemp	
				ReadTemp = readlong f
				if ReadTemp == 0x3f800000 then   
				(
					WriteLong nf ReadTemp
				)
				else -- Chris cutscene head has an unknown section that cause mod to crash
				(
					WriteLong nf 0x3f800000
					for i = 1 to 8 do
					(
						ReadTemp = ReadLong f
						WriteLong nf 0     -- write 0 to head of section to disable unknown section
					)
				)

				--padding
				                
				cur_pos = ftell f
                
                if (BoneCount > 0) then
                (
                    for i =1 to (ptr_Bone - cur_pos)/4 do
                    (
                        ReadTemp = ReadLong f 
                        WriteLong nf ReadTemp
                    )
                    
                    --if mod_ver==0x00D2 do 
                    --(
                    --	ReadTemp = readlong f 	
                    --	ukCount = ReadTemp
                    --	WriteLong nf ReadTemp					
                    --)
                    
                    --Bone ����Ҫ�Ķ�
                    
                    if RE5_ShouldUseExportVerboseDebug() do format "bonecount %\n" BoneCount
                    for i=1 to BoneCount do
                    (
                        BInfo = ReadBoneInfo f
                        WriteByte nf BInfo.ID
                        WriteByte nf BInfo.Parent
                        WriteByte nf BInfo.Child
                        WriteByte nf BInfo.uk1
                        WriteFloat nf BInfo.uk2
                        WriteFloat nf BInfo.uk3
                        WriteFloat nf BInfo.Trans.x
                        WriteFloat nf BInfo.Trans.y
                        WriteFloat nf BInfo.Trans.z
                        --format "BoneInfo %s\n" BInfo
                    )
                    --Bone Matrix ����Ҫ�Ķ�
                    for i=1 to BoneCount do
                    (		
                        for j=1 to 32 do
                        (
                            ReadTemp = readlong f 
                            WriteLong nf ReadTemp		
                        )						
                    )	
                    
                    --unknow
                    for i=1 to 256 do
                    (		
                        ReadTemp = readByte f 
                        WriteByte nf ReadTemp							
                    )	

                    new_ptr_BoneMap = ftell nf
                    --BoneMap ��֪��ʲô�ã����ø�
                    
                    BoneLUT = #()
                    BoneLUT.count = BoneMapCount
                    BoneMap = #()
                    BoneMap.count = BoneMapCount
                    BoneMapLen = #()
                    BoneMapRE5Id = #()
                    BoneMapRE5Id.count = BoneMapCount

                    i = 1
                    while i <= BoneMapCount do
                    (
                        BoneMap[i]= #()
                        BoneLUT[i] = #()
                        BoneLUT[i].count  = 255
                        idCount = Readlong f 
                        Writelong nf idCount	
                        BoneMapLen[i] = idCount
                        if RE5_ShouldUseExportVerboseDebug() do format "bonegroup % [%] :"  i idCount
                        local bone_id
                        for j=1 to idcount do
                        (
                            ReadTemp = readbyte f #unsigned
                            Writebyte nf ReadTemp	
                            
                            BoneMap[i][j]=ReadTemp
                            bone_id = ReadTemp + 1
                            if BoneLUT[i][bone_id] == undefined do BoneLUT[i][bone_id] = j  
                            if RE5_ShouldUseExportVerboseDebug() do format " %" ReadTemp						
                        )		
                        
                        left_to_read = 0   -- how many padding bytes to read
                        if ( idcount > 32 ) then
                        (
                            real_bm_cnt = ceil((idcount-32) /36.0 ) -- total # bone map to be read after first 32 bones.
                            left_to_read = real_bm_cnt *(4+32) - ( idcount - 32 );	
                            for j = 1 to real_bm_cnt do
                            (
                                i += 1
                                BoneMap[i]=#()
                                BoneMap[i].count=1
                                BoneMap[i][1]=0;
                                BoneLUT[i] = #()
                                BoneLUT[i].count  = 255							
                            )
                        )
                        else
                            left_to_read = 32 - idcount
                        
                        for j = 1 to left_to_read do
                        (
                            ReadTemp = readbyte f #unsigned
                            Writebyte nf ReadTemp	
                        )
                        i += 1
                        if RE5_ShouldUseExportVerboseDebug() do format "\n"					
                        if RE5_ShouldUseExportVerboseDebug() do format "bone tran %\n" BoneLUT[i]
                    )
                )
                else -- no bones, this is a stage mod file
                (
                      -- copy from base mod up to group section
                      long_cnt = ( ptr_Group - cur_pos ) /4
                      for i = 1 to long_cnt do
                      (
                            temp = ReadLong f #unsigned
                            WriteLong nf temp
                      )
                )
                
				--Mesh Info ���޸�û�иĶ���ģ��
				local ExportSelectionCandidates = RE5_BuildExportSelectionCandidates MeshCount ManualExportActionMode
				local HeaderOnlySelectionCandidates = RE5_BuildHeaderOnlySelectionCandidates MeshCount ManualExportActionMode
				local HeaderOnlySelectMeshInfo2 = #()
				local HeaderOnlyMeshSelIndex = #()
				local exportSelectionCount = 0
				local headerOnlySelectionCount = 0
				SelectMeshInfo = #()
				SelectMeshInfo2 = #()
				SelectMeshInfo.count = ExportSelectionCandidates.count
				SelectMeshCache = #()
				SelectMeshCache.count = ExportSelectionCandidates.count
				exportSelectionCount = ExportSelectionCandidates.count
				HeaderOnlySelectMeshInfo2.count = HeaderOnlySelectionCandidates.count
				HeaderOnlyMeshSelIndex.count = MeshCount
				for h = 1 to MeshCount do HeaderOnlyMeshSelIndex[h] = 0
				headerOnlySelectionCount = HeaderOnlySelectionCandidates.count
				if exportSelectionCount == 0 then
				(
					-- Header-only or delete-only export is still valid; do not abort here.
				)
				-- detect bonding volume changes 
				BoundChange = false
				NextBoneMapIndex = BoneMapCount + 1
				local minx, miny, minz, maxx, maxy, maxz, mx,my,mz,nx,ny,nz
				nx = minx = BoundMin.x
				mx = maxx = BoundMax.x
				ny = miny = BoundMin.y
				my = maxy = BoundMax.y
				nz = minz = BoundMin.z
				mz = maxz = BoundMax.z
                if RE5_ShouldUseExportVerboseDebug() do format "orig center % % % min % % % max % % %\n" ReadTempx ReadTempy ReadTempz minx miny minz maxx maxy maxz
				if RE5_ShouldUseExportVerboseDebug() do format "total sel %\n" exportSelectionCount
				-- recording selected mesh info
				for i=1 to exportSelectionCount do
				(
					local exportCandidate = ExportSelectionCandidates[i]
					local exportNode = undefined
					local exportMeshIndex = "0"
					local exportVertexType = ""
					local exportHeaderInfo = #(0,0,0,0)
					if exportCandidate != undefined and exportCandidate.count >= 4 do
					(
						exportNode = exportCandidate[1]
						exportMeshIndex = exportCandidate[2] as string
						exportVertexType = exportCandidate[3]
						exportHeaderInfo = exportCandidate[4]
					)
					sName = #()
					try (sName = filterString exportNode.name "_") catch(sName = #())
					SelectMeshInfo[i] = #(exportNode,exportMeshIndex,exportVertexType,i)		--#(Mesh, MeshIndex, VertexType)
					if sName.count == 7 then
					(
						mshHdr_matid = execute ((filterString sName[5] "x")[2])
						mshHdr_grp = execute ((filterString sName[6] "x")[2])
						mshHdr_mde = execute ((filterString sName[7] "x")[2])
						mshHdr_lod = execute ((filterString sName[4] "x")[2])
						SelectMeshInfo2[i] = #(mshHdr_matid,mshHdr_grp,mshHdr_mde,mshHdr_lod)
					)
					else
					(
						SelectMeshInfo2[i] = exportHeaderInfo
					)
				)
				for i=1 to headerOnlySelectionCount do
				(
					local headerCandidate = HeaderOnlySelectionCandidates[i]
					local headerMeshIndex = 0
					local headerInfo = #(0,0,0,0)
					if headerCandidate != undefined and headerCandidate.count >= 4 do
					(
						try (headerMeshIndex = headerCandidate[2] as integer) catch(headerMeshIndex = 0)
						headerInfo = headerCandidate[4]
					)
					HeaderOnlySelectMeshInfo2[i] = headerInfo
					if headerMeshIndex >= 1 and headerMeshIndex <= MeshCount do HeaderOnlyMeshSelIndex[headerMeshIndex] = i
				)
				bMeshSelect = #()
				bMeshSelect.count = MeshCount
				MeshSelIndex = #()
				MeshSelIndex.count = MeshCount		
				MeshBound = #()
                MeshBound.count = MeshCount
				RE5_SetProgress 16 (RE5_UIStr "分析选择" "Analyze selection")
				for i=1 to MeshCount do
				(
					bMeshSame = false
					sc = 0

					for j=1 to exportSelectionCount do
					(
						ind = execute SelectMeshInfo[j][2]
						if ind == i then
						(
							bMeshSame = true 
							sc = j
							break
						)
					)
					bMeshSelect[i] =bMeshSame
					MeshSelIndex[i] = sc
				)
				for i=1 to exportSelectionCount do
				(
					local selectedNode = SelectMeshInfo[i][1]
					local cacheNeedMap2 = false
					local cacheUseSkin = (BoneCount > 0)
					if BoneCount == 0 do try (cacheNeedMap2 = (RE5_GetNumMapVertsSafe selectedNode 2) > 0) catch(cacheNeedMap2 = false)
					SelectMeshCache[i] = RE5_BuildExportMeshCache selectedNode needMap2:cacheNeedMap2 useSkin:cacheUseSkin
				)
				fseek f ptr_Mesh #seek_set
				local ManualHeaderOnlyMeshOverride = #()
				ManualHeaderOnlyMeshOverride.count = MeshCount
				if ManualExportActionMode == #ok do ManualHeaderOnlyMeshOverride = RE5_BuildManualHeaderOnlyOverrideFlags MeshCount ManualExportActionMap HeaderOnlyMeshSelIndex HeaderOnlySelectMeshInfo2 f
				fseek f ptr_Mesh #seek_set
				local AutoHeaderOnlyMeshOverride = RE5_FindHeaderOnlySelectionIndices MeshCount MeshSelIndex bMeshSelect SelectMeshInfo2 SelectMeshCache f BoneCount BoundMin BoundMax BoneMap ptr_vertex OrgPtr_triangle
				HeaderOnlyMeshOverride = RE5_MergeHeaderOnlyOverrideFlags ManualHeaderOnlyMeshOverride AutoHeaderOnlyMeshOverride MeshCount
				fseek f ptr_Mesh #seek_set
                
                fn w_comp1 a b = (
                if a[1] > b[1] then -1
                else if a[1] < b[1] then 1
                else 0
                )		
				-- create bonemap for new mesh and merge this map with existing bonemap if possible
				for s=1 to MeshCount do
				(
					if s == 1 or s == MeshCount or (mod s 16) == 0 do RE5_SetProgress (16 + ((s as float / MeshCount) * 10.0)) (RE5_UIStr ("分析骨骼与边界 " + (s as string) + "/" + (MeshCount as string)) ("Analyze bones/bounds " + (s as string) + "/" + (MeshCount as string)))
					if bMeshSelect[s] == true do 
					(
						if ManualDeleteMeshFlags != undefined and s <= ManualDeleteMeshFlags.count and ManualDeleteMeshFlags[s] == true do continue
						if HeaderOnlyMeshOverride != undefined and HeaderOnlyMeshOverride[s] != undefined do continue
						i = MeshSelIndex[s]
						OutMesh = SelectMeshInfo[i][1]		--��Ӧѡ��� Mesh
						local analyzeCache = SelectMeshCache[i]
						local analyzeVerts = #()
						local analyzeWeights = #()
						if analyzeCache != undefined do
						(
							analyzeVerts = analyzeCache[1]
							analyzeWeights = analyzeCache[6]
						)
						vc = analyzeVerts.count
						theSkin = OutMesh.modifiers[#skin]
						local bc,b1,b2,b3,b4,w1,w2,w3,w4
						bone_map = #()
						local minx,miny,minz,maxx,maxy,maxz                        
						for c = 1 to vc do 
						(					
							-- get bounding volume for new mesh, expand character bounding volume if needed
							vPos = analyzeVerts[c]
							vPos = [ vPos.x, vPos.z, -vPos.y ]    -- convert from 3ds to re5 axis
                            if (c == 1) then
                                ( 
                                    minx = vPos.x; maxx = vPos.x 
                                    miny = vPos.y; maxy = vPos.y
                                    minz = vPos.z; maxz = vPos.z
                                )
                               else
                               (
							if vPos.x > maxx then  (  maxx = vPos.x)
								else if vPos.x < minx then (  minx = vPos.x )
							if vPos.y > maxy then  (  maxy = vPos.y )
								else if vPos.y < miny then (   miny = vPos.y)
							if vPos.z > maxz then  (   maxz = vPos.z )
								else if vPos.z < minz then (   minz = vPos.z )
                                )
                            
                            if (BoneCount > 0) do
                            (
                                -- create a bonemap for new mesh
                                w_array = analyzeWeights[c]
                                if w_array == undefined do w_array = #()
                                bc = w_array.count
                                    
                                if bc > 3 do ( b4 = w_array[4][2]; w4 = w_array[4][1]; if  w4 > 0 do appendIfUnique  bone_map (b4 - 1 ))
                                if bc > 2 do ( b3 = w_array[3][2]; w3 = w_array[3][1]; if  w3 > 0 do appendIfUnique  bone_map (b3 - 1 ))
                                if bc > 1 do ( b2 = w_array[2][2]; w2 = w_array[2][1]; if  w2 > 0 do appendIfUnique  bone_map (b2 - 1 ))
                                if bc > 0 do ( b1 = w_array[1][2]; w1 = w_array[1][1]; if  w1 > 0 do appendIfUnique  bone_map (b1 - 1 ))
                            )
							
						)
                        if RE5_ShouldUseExportVerboseDebug() do format " mesh % min % % % max % % %\n" s nx ny nz mx my mz
                        if minx < nx do (nx = minx;BoundChange = true)
                        if maxx > mx do (mx = maxx;BoundChange = true) 
                        if miny < ny do (ny = miny;BoundChange = true) 
                        if maxy > my do (my = maxy;BoundChange = true) 
                        if minz < nz do (nz = minz;BoundChange = true)
                        if maxz > mz do (mz = maxz;BoundChange = true)
                        bnd = BoundInfo()
                        bnd.nx = minx; bnd.ny = miny; bnd.nz = minz
                        bnd.mx = maxx; bnd.my = maxy; bnd.mz = maxz
                        bnd.cx = (maxx-minx) /2.0 + minx
                        bnd.cy = (maxy-miny) /2.0 + miny 
                        bnd.cz = (maxz-minz) /2.0 + minz
                        MeshBound[s] = bnd
                        
						--format " mesh % min % % % max % % %\n" s minx miny minz maxx maxy maxz
                        --format " mesh % min % % % max % % %\n" s nx ny nz mx my mz
						--format "boundbox %\n" BoundChange
                        
                        if (BoneCount >0) do
                        (
                            sort bone_map
                            
                            no_of_bone = bone_map.count
                            if  no_of_bone > 32 then
                                no_of_bg = 1 + ceil((no_of_bone-32) /36.0) 	-- round up to multiple of 36 bytes
                            else
                                no_of_bg = 1
                            total_map_size = no_of_bg*(4+32)   	-- this is a RE5 hack to support > 32 bones map
                            if RE5_ShouldUseExportVerboseDebug() do format "mesh gid % no_bg % totsize % bonemap [%] %\n"  NextBoneMapIndex no_of_bg total_map_size bone_map.count bone_map
                            
                            -- try to match new mesh to existing bone map
                            newMapId = 0
                            local notfound  = true 
                            local uniq
                            for k = 1 to BoneMapCount while notfound do
                            (
                                
                                combine = BoneMap[k] + bone_map
                                uniq = makeUniqueArray combine
                                if uniq.count == BoneMapLen[k] do    -- combine size less than 32 bones, merge successful
                                (
                                    
                                    if RE5_ShouldUseExportVerboseDebug() do format " combine % % %\n" k uniq.count BoneMap[k]								
                                    newMapId = k
                                    notfound = false
                                )
                                
                            )
                
                            if newMapId > 0 then   -- found reusable  bonemap,  point new mesh to it
                            (
                                SelectMeshInfo2[i][2] = (newMapId - 1)  -- 0 based bonemap id, for internal lookup
                                if  BoneMapRE5Id[newMapId] != undefined then  -- record runtime bone map for this mesh
                                    SelectMeshInfo2[i][5] = BoneMapRE5Id[newMapId]
                                else
                                    SelectMeshInfo2[i][5] = (newMapId - 1)
                            )
                            else
                            (
                                -- otherwise create a new bonemap and save , new map can be bigger than 32 entires
                                BoneMapCount += 1
                                BoneMap[BoneMapCount] = bone_map
                                BoneMapLen[BoneMapCount] = no_of_bone
                                BoneLUT[BoneMapCount] = #()
                                BoneLUT[BoneMapCount].count  = 255

                                -- write new bone_group
                                writelong nf no_of_bone
                                for j = 1 to no_of_bone do
                                (
                                    bone_id = bone_map[j]
                                    writebyte nf bone_id
                                    bone_id += 1
                                    if BoneLUT[BoneMapCount][bone_id] == undefined do BoneLUT[BoneMapCount][bone_id] = j  
                                )
                                -- pad to fill multiple of 32 bone entries
                                if  (no_of_bone +4) < total_map_size do
                                (
                                    for j = 1 to total_map_size - (no_of_bone + 4) do
                                         writebyte nf 0
                                )		
                                --for k = 1 to bone_map.count do
                                --	format " %(%)" k bone_map[k]
                                --format "\n"
                                --for k = 1 to 255 do
                                --	format " %(%)" k BoneLUT[BoneMapCount][k]
                                --format "\n"
                                
                                SelectMeshInfo2[i][2] = (BoneMapCount - 1)  -- 0 based bonemap id, for internal lookup							
                                SelectMeshInfo2[i][5] = ( NextBoneMapIndex - 1)   --  RE5  runtime bone map id base on 32 entry map limit.
                                BoneMapRE5Id[BoneMapCount] = ( NextBoneMapIndex - 1) 
                                
                                --format "grp % lut %\n" BoneMapCount BoneLUT[BoneMapCount]

                                NextBoneMapIndex += no_of_bg
                            )
						) --end BoneCount > 0
					)
				
				)
				
				new_ptr_Group = ftell nf 				
				fseek f ptr_Group #seek_set
				-- Group info
				for i=1 to GroupCount do
				(
					for j = 1 to 8 do
					(
						ReadTemp = Readlong f #unsigned
						Writelong nf ReadTemp									
					)
				)
				
				new_ptr_Texture = ftell nf
				for i=1 to TextureCount do
				(
					for j=1 to 64 do
					(
						ch = ReadByte f #unsigned 
						WriteByte nf ch
					)
				)
				
				--Mat ID �Ͳ����ļ��йأ�����Ҫ�Ķ���ģ��Ĭ�ϵĲ��ʹ���
                MatArray = #()
                MatArray.count = MatCount               

				for i=1 to MatCount do
				(
                    
                    if (BoneCount == 0 ) then -- need Material info for stage objects
                    (
                        for j = 1 to 6 do  
                        (
                            temp  = ReadLong f #unsigned
                            WriteLong nf temp
                        )
                            MatArray[i]= MatInfo()  	
							MatArray[i].Tex = #()
							MatArray[i].Tex.count = 8						
                        for j = 1 to 8 do  
                        ( 

                            MatArray[i].Tex[j]  = ReadLong f #unsigned
                            WriteLong nf MatArray[i].Tex[j]                            
                        )
                        if MatArray[i].Tex[2] > 0 then MatArray[i].hasNorMap = true else MatArray[i].hasNorMap = false        
                        if MatArray[i].Tex[4] > 0 then MatArray[i].hasLgtMap = true else MatArray[i].hasLgtMap = false       
                        if MatArray[i].Tex[6] > 0 then MatArray[i].hasAmbMap = true else MatArray[i].hasAmbMap = false
                        
                        for j = 1 to 26 do  --  color attributes
                        (
                            temp = ReadLong f #unsigned
                            WriteLong nf temp
                        )
                    )
                    else
                    (
                        cnt = 40                        
                        -- 0x89 material type only works with vertex with 8 bones, we already convert all vertex to 4 bones. so  convert 0x89  to 0x81,  
                        flags = ReadLong f
                        if flags == undefined then
                        (
                            local matReadPos = 0
                            try (matReadPos = ftell f) catch(matReadPos = -1)
                            throw ("RE5 export material read failed at material " + (i as string) + "/" + (MatCount as string) + ", ptr_Group=" + (ptr_Group as string) + ", ptr_Texture=" + (ptr_Texture as string) + ", filePos=" + (matReadPos as string) + ", note=sequential group->texture->material copy path")
                        )
                        --if ( bit.shift  flags -24 ) == 0x89 then
                        if (bit.and flags 0x08000000) != 0 then
                        (
                            WriteLong nf ( flags - 0x08000000 ) 
                            ReadTemp = readlong f
                            WriteLong nf ( ReadTemp - 1)		
                            ReadTemp = readlong f 
                            WriteLong nf ReadTemp								
                            ReadTemp = readlong f
                            WriteLong nf ( ReadTemp - 1)								
                        )
                        else
                        (
                            WriteLong nf flags
                            ReadTemp = readlong f 
                            WriteLong nf ReadTemp	
                            ReadTemp = readlong f 
                            WriteLong nf ReadTemp	
                            ReadTemp = readlong f 
                            WriteLong nf ReadTemp							
                        )					
                        cnt = 40 - 4
                        --if mod_ver==0x00D2 do (cnt=32)
                        for j=1 to cnt do
                        (
                            ReadTemp = readlong f 
                            WriteLong nf ReadTemp		
                        )
                    )
				)	
								
				--print SelectMeshInfo
				new_ptr_Mesh = ftell nf
				RE5_SetProgress 28 (RE5_UIStr "写入 Mesh 表" "Write mesh table")
					
				NewMeshInfo = #()
				NewMeshInfo.count = MeshCount
			
				local OrgMeshInfo
				local bSaveMesh = false
				local LastSimpleMesh
				for i=1 to MeshCount do
				(
					if i == 1 or i == MeshCount or (mod i 16) == 0 do RE5_SetProgress (28 + ((i as float / MeshCount) * 12.0)) (RE5_UIStr ("处理 Mesh 表 " + (i as string) + "/" + (MeshCount as string)) ("Process mesh table " + (i as string) + "/" + (MeshCount as string)))
					OrgMeshInfo = ReadMeshHeader f
					OrgMeshInfo_Array					
					bMeshSame = bMeshSelect[i]
					sc = MeshSelIndex[i]
					local BoneGrpId
					local headerOnlyOverride = #(false,false,false,false,false,OrgMeshInfo.MatId,OrgMeshInfo.bonemapindex,OrgMeshInfo.lodLevel,OrgMeshInfo.unk07)
					local useHeaderOnlyOverride = false
					if HeaderOnlyMeshOverride != undefined and i <= HeaderOnlyMeshOverride.count and HeaderOnlyMeshOverride[i] != undefined do
					(
						headerOnlyOverride = HeaderOnlyMeshOverride[i]
						useHeaderOnlyOverride = true
					)
					if useHeaderOnlyOverride == true then
					(
						if RE5_ShouldUseExportVerboseDebug() do format "RE5 write header-only mesh % mat:% grp:% disp:% lod:%\n" i headerOnlyOverride[6] headerOnlyOverride[7] headerOnlyOverride[9] headerOnlyOverride[8]

						writeshort nf OrgMeshInfo.meshtype
						writeshort nf headerOnlyOverride[6]
						writebyte nf OrgMeshInfo.unk01
						writebyte nf headerOnlyOverride[8]
						writeshort nf OrgMeshInfo.unk02		
						writebyte nf OrgMeshInfo.vertStride		
                        if (BoneCount > 0 ) then
                            writebyte nf 0x00
                        else
                            writebyte nf OrgMeshInfo.vertFlag
						writeshort nf OrgMeshInfo.unk04						
						writeshort nf OrgMeshInfo.vertCount
						vc = OrgMeshInfo.vertCount
						writeshort nf OrgMeshInfo.vertEnd
						
						writelong nf OrgMeshInfo.vertStart
						writelong nf OrgMeshInfo.vertBase
						writelong nf OrgMeshInfo.vertBase2
						
						writelong nf OrgMeshInfo.faceStart
						writelong nf OrgMeshInfo.faceCount
						writelong nf OrgMeshInfo.faceBase
						fc = OrgMeshInfo.faceCount
						
						writebyte nf OrgMeshInfo.unk06
						writebyte nf headerOnlyOverride[9]
						writeshort nf OrgMeshInfo.vertStart2
						writebyte nf OrgMeshInfo.weightmaps		
						
						writebyte nf headerOnlyOverride[7]
						BoneGrpId = headerOnlyOverride[7]
						writebyte nf OrgMeshInfo.min_index 
						writebyte nf OrgMeshInfo.max_index
						
						writelong nf OrgMeshInfo.unk09
						NewMeshInfo[i] = #(false,OrgMeshInfo.vertFlag,OrgMeshInfo.vertStride,vc,fc,0,OrgMeshInfo.min_index,OrgMeshInfo.vertBase)
						NewMeshInfo[i][21] = true
						NewMeshInfo[i][22] = headerOnlyOverride
					)
					else if ManualDeleteMeshFlags != undefined and i <= ManualDeleteMeshFlags.count and ManualDeleteMeshFlags[i] == true then
					(
						writeshort nf OrgMeshInfo.meshtype
						writeshort nf OrgMeshInfo.MatId
						writebyte nf OrgMeshInfo.unk01
						writebyte nf OrgMeshInfo.lodLevel
						writeshort nf OrgMeshInfo.unk02
						writebyte nf OrgMeshInfo.vertStride
						if (BoneCount > 0 ) then
							writebyte nf 0x00
						else
							writebyte nf OrgMeshInfo.vertFlag
						writeshort nf OrgMeshInfo.unk04
						writeshort nf 0
						vc = 0
						writeshort nf 0
						writelong nf OrgMeshInfo.vertStart
						writelong nf OrgMeshInfo.vertBase
						writelong nf OrgMeshInfo.vertBase2
						writelong nf OrgMeshInfo.faceStart
						writelong nf 0
						writelong nf OrgMeshInfo.faceBase
						fc = 0
						writebyte nf OrgMeshInfo.unk06
						writebyte nf OrgMeshInfo.unk07
						writeshort nf OrgMeshInfo.vertStart2
						writebyte nf OrgMeshInfo.weightmaps
						writebyte nf OrgMeshInfo.bonemapindex
						BoneGrpId = OrgMeshInfo.bonemapindex
						writebyte nf OrgMeshInfo.min_index
						writebyte nf OrgMeshInfo.max_index
						writelong nf OrgMeshInfo.unk09
						NewMeshInfo[i] = #(false,OrgMeshInfo.vertFlag,OrgMeshInfo.vertStride,0,0,0,OrgMeshInfo.min_index,OrgMeshInfo.vertBase)
						NewMeshInfo[i][21] = false
						NewMeshInfo[i][22] = undefined
						NewMeshInfo[i][23] = true
					)
					else if bMeshSame == true then	--ͬ����ģ���滻
					(
						writeshort nf OrgMeshInfo.meshtype
						vc = SelectMeshCache[sc][1].count
							
						if SelectMeshInfo2.count!=0 then 
						(
							writeshort nf SelectMeshInfo2[sc][1] --Is this valid?,  update Mat Id
							--writeshort nf OrgMeshInfo.MatId
							writebyte nf OrgMeshInfo.unk01
							writebyte nf SelectMeshInfo2[sc][4] -- update lod level
							writeshort nf OrgMeshInfo.unk02
							writebyte nf OrgMeshInfo.vertStride
							--writebyte nf OrgMeshInfo.vertFlag
							--OrgMeshInfo.vertFlag = 0x00
                            if (BoneCount > 0) then
                                writebyte nf 0x80
                            else
                                writebyte nf (bit.or 0x80 OrgMeshInfo.vertFlag)   -- special flag indicates triangle list 
							writeshort nf OrgMeshInfo.unk04  --SelectMeshInfo2[sc][3]
						)
						else
						(
							writeshort nf OrgMeshInfo.MatId
							writebyte nf OrgMeshInfo.unk01
							writebyte nf OrgMeshInfo.lodLevel
							writeshort nf OrgMeshInfo.unk02
							writebyte nf OrgMeshInfo.vertStride
							--writebyte nf OrgMeshInfo.vertFlag
							--OrgMeshInfo.vertFlag = 0x00
                            if (BoneCount > 0) then
                                writebyte nf 0x80
                            else                            
                                writebyte nf (bit.or 0x80 OrgMeshInfo.vertFlag)   -- special flag indicates triangle list 
							writeshort nf OrgMeshInfo.unk04
						)
						
						writeshort nf vc
 						writeshort nf 	OrgMeshInfo.vertEnd							
						writelong nf OrgMeshInfo.vertStart
						writelong nf OrgMeshInfo.vertBase
						writelong nf OrgMeshInfo.vertBase2
							
						writelong nf OrgMeshInfo.faceStart
						
						fc = SelectMeshCache[sc][3].count		

						fc *= 3
						writelong nf fc
						--format " orignal vc % new vc % orig fc % new fc % \n" OrgMeshInfo.vertCount vc OrgMeshInfo.faceCount fc

						writelong nf OrgMeshInfo.faceBase
						
						if false then -- ( OrgMeshInfo.unk06 == 7 )  then   -- this mesh use 2nd vertex stream to support 8 bones, donwgrade it to 4 bones
						(											-- change vertex definition index
						writebyte nf 5
						writebyte nf 0
						)
						else
						(
						writebyte nf OrgMeshInfo.unk06
						writebyte nf OrgMeshInfo.unk07
						)
						
						writeshort nf OrgMeshInfo.vertStart2
						writebyte nf OrgMeshInfo.weightmaps
						
						if BoneCount > 0 and SelectMeshInfo2.count!=0 then    -- bone group index
						(		
							writebyte nf SelectMeshInfo2[sc][5]   -- index for RE5 runtime, 
							BoneGrpId = SelectMeshInfo2[sc][2]  -- index for internal look up 
						)
						else
						(
							writebyte nf OrgMeshInfo.bonemapindex
							BoneGrpId = OrgMeshInfo.bonemapindex
						)	
						writebyte nf OrgMeshInfo.min_index							
						writebyte nf OrgMeshInfo.max_index							
						writelong nf OrgMeshInfo.unk09
						
						NewMeshInfo[i] = #(true,OrgMeshInfo.vertFlag,OrgMeshInfo.vertStride,vc,fc,sc,OrgMeshInfo.min_index,OrgMeshInfo.vertBase)
						
						NewMeshInfo[i][16] = fc 

					)else
					(

						writeshort nf OrgMeshInfo.meshtype
						writeshort nf OrgMeshInfo.MatId					
						writebyte nf OrgMeshInfo.unk01
						writebyte nf OrgMeshInfo.lodLevel
						writeshort nf OrgMeshInfo.unk02		
						writebyte nf OrgMeshInfo.vertStride		
						--writebyte nf OrgMeshInfo.vertFlag
						--OrgMeshInfo.vertFlag = 0x00
                        if (BoneCount > 0 ) then
                            writebyte nf 0x00 -- support only one vertex format ( max 4 bones for character,  max 3 uv maps  for stages)
                        else
                            writebyte nf OrgMeshInfo.vertFlag  -- do not change stage mod file vert type
                            
						writeshort nf OrgMeshInfo.unk04						
						writeshort nf OrgMeshInfo.vertCount
						vc = OrgMeshInfo.vertCount
						writeshort nf OrgMeshInfo.vertEnd
						
						writelong nf OrgMeshInfo.vertStart
						writelong nf OrgMeshInfo.vertBase
						writelong nf OrgMeshInfo.vertBase2
						--writelong nf OrgMeshInfo.fvfInfo
						
						writelong nf OrgMeshInfo.faceStart
						writelong nf OrgMeshInfo.faceCount
						writelong nf OrgMeshInfo.faceBase
						fc = OrgMeshInfo.faceCount -- visible face index size
						
						writebyte nf OrgMeshInfo.unk06
						writebyte nf OrgMeshInfo.unk07
						writeshort nf OrgMeshInfo.vertStart2
						writebyte nf OrgMeshInfo.weightmaps		
						
						writebyte nf OrgMeshInfo.bonemapindex
						BoneGrpId = OrgMeshInfo.bonemapindex
						writebyte nf OrgMeshInfo.min_index 
						writebyte nf OrgMeshInfo.max_index
						
						writelong nf OrgMeshInfo.unk09
						NewMeshInfo[i] = #(false,OrgMeshInfo.vertFlag,OrgMeshInfo.vertStride,vc,fc,0,OrgMeshInfo.min_index,OrgMeshInfo.vertBase)
						
					)
					if NewMeshInfo[i][21] == undefined do NewMeshInfo[i][21] = false
					if NewMeshInfo[i][22] == undefined do NewMeshInfo[i][22] = undefined
					if NewMeshInfo[i][23] == undefined do NewMeshInfo[i][23] = false
					NewMeshInfo[i][10] = OrgMeshInfo.vertCount*OrgMeshInfo.vertStride	
					NewMeshInfo[i][11] = OrgMeshInfo.faceCount

					if ( i > 1 ) and ( NewMeshInfo[i-1][13] == undefined ) then   -- real face index size
						NewMeshInfo[i-1][13] = OrgMeshInfo.faceStart - NewMeshInfo[i-1][15] 

					NewMeshInfo[i][14] = BoneGrpId
					NewMeshInfo[i][15] = OrgMeshInfo.faceStart
					NewMeshInfo[i][17] = OrgMeshInfo.vertStart
                    NewMeshInfo[i][18] = OrgMeshInfo.vertBase/32 + OrgMeshInfo.faceBase + OrgMeshInfo.vertStart    -- original absolute vert start 
				)
				NewMeshInfo[MeshCount][13] = OrgFaceCount - NewMeshInfo[MeshCount][15] -- OrgMeshInfo.faceCount + 2   -- last mesh index size
				
				--?? 
				--if mod_ver!=0x00D2 do 
				
				( 
					--  bone weight list??
					ukCount = readlong f
					WriteLong nf ukCount
				)
				if RE5_ShouldUseExportVerboseDebug() do format "Blob count %\n" ukCount
                if (BoneCount >0) then
                (
                    for i=1 to ukCount do
                    (
                        for j=1 to 36 do 
                        (
                            ReadTemp = readlong f 
                            WriteLong nf ReadTemp
                        )
                    )
                )
                else
                (
                    -- stage mod , calculate bone bound per mesh
                    for i=1 to ukCount do
                    (
                        if NewMeshInfo[i][1] == true then
                        (
                            for j = 1 to 4 do
                            (
                                ReadTemp = readlong f
                                WriteLong nf ReadTemp 
                            )
                            for j = 1 to 7 do ReadTemp = readlong f
                            WriteFloat nf MeshBound[i].cx
                            WriteFloat nf MeshBound[i].cy
                            WriteFloat nf MeshBound[i].cz
                            dx = MeshBound[i].mx - MeshBound[i].nx
                            dy = MeshBound[i].my - MeshBound[i].ny
                            dz = MeshBound[i].mz - MeshBound[i].nz
                            WriteFloat nf (sqrt(dx*dx + dy*dy + dz *dz))
                            WriteFloat nf MeshBound[i].nx
                            WriteFloat nf MeshBound[i].ny
                            WriteFloat nf MeshBound[i].nz
                                ReadTemp = readlong f
                                WriteLong nf ReadTemp   
                                
                            for j = 1 to 3 do ReadTemp = readlong f                                
                            WriteFloat nf MeshBound[i].mx
                            WriteFloat nf MeshBound[i].my
                            WriteFloat nf MeshBound[i].mz
                                ReadTemp = readlong f
                                WriteLong nf ReadTemp   
                            for j = 1 to 12 do ReadTemp = readlong f 
                            WriteFloat nf 1.0; WriteFloat nf 0.0; WriteFloat nf 0.0; WriteFloat nf 0.0
                            WriteFloat nf 0.0; WriteFloat nf 1.0; WriteFloat nf 0.0; WriteFloat nf 0.0
                            WriteFloat nf 0.0; WriteFloat nf 0.0; WriteFloat nf 1.0; WriteFloat nf 0.0
                            for j = 1 to 8 do ReadTemp = readlong f 
                            WriteFloat nf MeshBound[i].cx
                            WriteFloat nf MeshBound[i].cy
                            WriteFloat nf MeshBound[i].cz
                            WriteFloat nf 1.0
                            WriteFloat nf (MeshBound[i].mx - MeshBound[i].cx)
                            WriteFloat nf (MeshBound[i].my - MeshBound[i].cy)
                            WriteFloat nf (MeshBound[i].mz - MeshBound[i].cz)
                            WriteFloat nf -1.0
                        )
                        else
                        for j=1 to 36 do 
                        (
                            ReadTemp = readlong f 
                            WriteLong nf ReadTemp
                        )
                    )
                
                )

				new_ptr_Vertex = ftell nf
				RE5_SetProgress 42 (RE5_UIStr "写入顶点" "Write vertices")
				--vertex ����
				local xr,yr,zr,newxl,newyl,newzl,offsetx,offsety,offsetz
                    maxx=mx
                    minx=nx
                    maxy=my
                    miny=ny
                    maxz=mz
                    minz=nz
				newxl = maxx - minx
				newyl = maxy - miny
				newzl = maxz - minz

				if BoundChange == true and (BoneCount > 0) do -- character bounding box change, need to resize all vertices
				(
					xr = (BoundMax.x - BoundMin.x)/ newxl     -- scale factor adjust old mesh for new bounding box
					yr = (BoundMax.y - BoundMin.y)/ newyl
					zr = (BoundMax.z - BoundMin.z)/ newzl
					offsetx = (minx - BoundMin.x)*32767.0/newxl  -- position adjustment for old mesh.
					offsety = (miny - BoundMin.y)*32767.0/newyl
					offsetz = (minz - BoundMin.z)*32767.0/newzl
				)
					
				for i=1 to MeshCount do
				(
					if i == 1 or i == MeshCount or (mod i 8) == 0 do RE5_SetProgress (42 + ((i as float / MeshCount) * 32.0)) (RE5_UIStr ("写入顶点 " + (i as string) + "/" + (MeshCount as string)) ("Write vertices " + (i as string) + "/" + (MeshCount as string)))
					vc = NewMeshInfo[i][4]
					vs = NewMeshInfo[i][3]
					if NewMeshInfo[i][23] == true then
					(
						local skipVertexBytes = NewMeshInfo[i][10]
						if skipVertexBytes > 0 do fseek f skipVertexBytes #seek_cur
						NewMeshInfo[i][9] = (ftell nf) - new_ptr_Vertex
						continue
					)
					
					if NewMeshInfo[i][1] == false then	--����Ҫ�޸Ķ���ֱ�Ӹ���
					(				
						local useCharacterFastCopy = false
						local originalVertexBytes = NewMeshInfo[i][10]
						if BoneCount > 0 then
						(
							useCharacterFastCopy = (RE5_IsExportOptimizationEnabled RE5ExportFastCopyUnchangedCharacterMeshes and BoundChange == false and NewMeshInfo[i][2] != 0x08 and originalVertexBytes > 0)
						)
						if useCharacterFastCopy == true then
						(
							RE5_CopyBinaryRange f nf originalVertexBytes
						)
						else
						(
							vs /= 4
							for v=1 to vc do
							(
	                            if (BoneCount == 0) then  -- stage mod file does not need normalize vertex
	                            (
	                                for s = 1 to (32/4) do  -- copy vertex as-is
	                                (
	                                    temp = ReadLong f #unsigned
	                                    WriteLong nf temp
	                                )
	                            )                            
	                            else                         
	                            (
	                                vPos = [(ReadShort f), (ReadShort f), (ReadShort f)]
	                                if BoundChange == true then
	                                (
	                                    vPos[1]= vPos[1]*xr - offsetx
	                                    vPos[2]= vPos[2]*yr - offsety
	                                    vPos[3]= vPos[3]*zr - offsetz
	                                    
	                                )
	                                
	                                WriteShort nf vPos[1]
	                                WriteShort nf vPos[2]
	                                WriteShort nf vPos[3]
	                                
	                                tempShort = readShort f   -- always 7fff
	                                WriteShort nf tempShort
	                                
	                                if  NewMeshInfo[i][2] == 0x08 then   --  this mesh use 8 bones vertex format, convert to 4 bone format
	                                (
	                                    bb = #()
	                                    bb.count = 8
	                                    b_array = #()
	                                    b_array.count = 8
	                                    for j = 1 to 8 do
	                                        bb[j] = ReadByte f  #unsigned
	                                    for j = 1 to 8 do
	                                    (
	                                        ww = ReadByte f  #unsigned
	                                        b_array[j] = #(ww,bb[j])
	                                    )
	                                    qsort b_array w_comp1
	                                    -- make sure bone weight sum up to 255
	                                    b1= b_array[1][2]
	                                    b2= b_array[2][2]
	                                    b3= b_array[3][2]
	                                    b4= b_array[4][2]
	                                    w1= b_array[1][1]
	                                    w2= b_array[2][1]
	                                    w3= b_array[3][1]
	                                    w4= b_array[4][1]
	                                    
	                                    
	                                    wt = w1+w2+w3+w4								
	                                    wt = 255.0 /wt 
	                                    w1 = ( w1*wt +0.5 ) as integer
	                                    w2 = ( w2*wt +0.5 ) as integer
	                                    w3 = ( w3*wt +0.5 ) as integer
	                                    w4 = ( w4*wt +0.5 ) as integer
	                                    adj = 255 - (w1+w2+w3+w4)
	                                    w1+= adj
	                                    
	                                    --if i == 29 do format " v % % % % % % % % %\n" v b1 b2 b3 b4 w1 w2 w3 w4
	                                    
	                                    for j = 1 to 4 do    -- write bone id
	                                        WriteByte nf b_array[j][2]
	                                      -- write weight
	                                    WriteByte nf w1 ; WriteByte nf w2 ; WriteByte nf w3 ; WriteByte nf w4
	                                    
	                                    normx = Readbyte f #unsigned  -- normal 
	                                    normy = Readbyte f #unsigned
	                                    normz = Readbyte f #unsigned
	                                    normw = Readbyte f #unsigned
	                                    Writebyte nf normx
	                                    Writebyte nf normy
	                                    Writebyte nf normz
	                                    Writebyte nf normw
	                                    
	                                    u1 = ReadShort f
	                                    v1 = ReadShort f
	                                    uvwy = ReadFloat16 v1
	                                    -- tangent
	                                    if  normx == 127 and normy == 127 and normz == 127 then
	                                    (
	                                        vTan = [normx,normy,normz]
	                                    )
	                                    else
	                                    (
	                                        vTan = Normalize( vPos/uvwy)
	                                        vTan *= 127.0; vTan += 127
	                                    )	
	                                    WriteByte nf vTan.x; WriteByte nf vTan.y; WriteByte nf vTan.z; WriteByte nf 255
	                                    -- uv
	                                    WriteShort nf u1
	                                    WriteShort nf v1
	                                    WriteShort nf (0xffff)
	                                    WriteShort nf (0xffff)										
	                                    
	                                )
	                                else
	                                (
	                                    for s=3 to vs do			  
	                                    (
	                                        ReadTemp = readlong f #unsigned
	                                        WriteLong nf ReadTemp	
	                                    )
	                                )
	                            ) -- bcount > 0
	                            
							)
						)
					)else
					(
						--format " mesh % selected\n" i
						vcs = NewMeshInfo[i][10]

						fseek f vcs #seek_cur	--����
						si = NewMeshInfo[i][6]
						OutMesh = SelectMeshInfo[si][1]		--��Ӧѡ��� Mesh
						local exportMeshCache = SelectMeshCache[si]
						local exportVerts = exportMeshCache[1]
						local exportUV1 = exportMeshCache[2]
						local exportFaces = exportMeshCache[3]
						local exportUV2 = exportMeshCache[4]
						local NormArray = exportMeshCache[5]
						local skinWeightCache = exportMeshCache[6]
						local colorCache = exportMeshCache[7]
						theSkin = exportMeshCache[8]
						theNorm = exportMeshCache[9]
						
						local bi1,bi2,bi3,bi4,b1,b2,b3,b4,b5,b6,w1,w2,w3,w4,w5,w6	--bone weight
						--format "new vc % vs % \n" vc vs
 						--MeshScale = 32768/($b_0_1.scale)
						--case NewMeshInfo[i][2] of
                        
                        if (BoneCount == 0 ) then -- stage mod file
                        (
                            matid = SelectMeshInfo2[NewMeshInfo[i][6]][1]
                            hasLgtMap =  MatArray[matid+1].hasLgtMap
                            hasNorMap =  MatArray[matid+1].hasNorMap
							if RE5_ShouldUseExportVerboseDebug() do format " mesh % hasnor % haslgt %\n" i hasNorMap hasLgtMap
							if RE5_ShouldUseExportVerboseDebug() do format "total color vert % %\n" vc (getNumCPVVerts OutMesh)
                            --setNumCPVVerts OutMesh vc true
                            for c=1 to vc do
                            (
                                vPos = exportVerts[c]
								vPos = [  vPos.x, vPos.z, -vPos.y] -- need to flip y and z 																														
								vNorm = NormArray[c]                                
								--format "vNorm % " vNorm
								vNorm *= 127.0; vNorm += 127
							    --format "vNorm % \n" vNorm
								uvw = exportUV1[c]								
										
								uvw.y = 1.0 - uvw.y 
								
								if  NormArray[c].x == 0 and NormArray[c].y == 0 and NormArray[c].z == 0 then
								(
									--format "mesh % v % norm = 0\n" i c
									vTan = NormArray[c]
								)
								else
								(
									--if i == 13 do format "v % norm/uv\n" c
									vTan = Normalize( vPos/uvw.y)
								)
								vTan *= 127.0; vTan += 127
                                WriteFloat nf vPos.x; WriteFloat nf vPos.y; WriteFloat nf vPos.z
								WriteByte nf vNorm.x; WriteByte nf vNorm.y; WriteByte nf vNorm.z; WriteByte nf 255
								WriteByte nf vTan.x; WriteByte nf vTan.y; WriteByte nf vTan.z; WriteByte nf 255

                                -- diffuse map uv
								u1 = FShort uvw.x
								v1 = FShort uvw.y
								WriteShort nf (u1)
								WriteShort nf (v1)
                                if (hasNorMap == true) do
                                (
                                    WriteShort nf (u1)
                                    WriteShort nf (v1)                                    
                                )                                
                                if (hasLgtMap == true) then -- light map uv from channel 2
                                (
                                    uvw = exportUV2[c]
                                    if uvw == undefined do uvw = exportUV1[c]
                                    uvw.y = 1.0 - uvw.y 
                                    
                                    WriteShort nf (FShort uvw.x)
                                    WriteShort nf (FShort uvw.y)     
								
                                    if (hasNorMap == false) then -- pad to 32 bytes
                                    (
                                        WriteShort nf (0xffff)
                                        WriteShort nf (0xffff)      
                                    ) 							
                                )
                                else
								(
                                    if (hasNorMap == false) then -- pad to 32 bytes
                                    (
                                        WriteShort nf (0xffff)
                                        WriteShort nf (0xffff)      
                                    ) 	   
									color = colorCache[c]
									if color == undefined do color = black
									--format "mesh % color %  %\n" i color color.a
									WriteByte nf color.r
                                    WriteByte nf color.g
                                    WriteByte nf color.b
                                    WriteByte nf color.a
								)
							
    

                            )
                        )
                        else
						(                        
							--32
							--(0x00): 
							for c=1 to vc do --withskin x y z w i1 i2 i3 i4 w1 w2 w3 w4 nx ny nz nw tx ty tz tw u1 v1 u2 v2
							(
								vPos = exportVerts[c]  --*MeshScale
								vPos = [
								(vPos.x-minx)*32767.0/newxl,
								(vPos.z-miny)*32767.0/newyl,    -- need to flip y and z 
								(-vPos.y-minz)*32767.0/newzl ]
								
								vNorm = NormArray[c]
								--format "vNorm % " vNorm
								vNorm *= 127.0; vNorm += 127
							    --format "vNorm % \n" vNorm
								uvw = exportUV1[c]								
										
								uvw.y = 1.0 - uvw.y 
								
								if  NormArray[c].x == 0 and NormArray[c].y == 0 and NormArray[c].z == 0 then
								(
									--format "mesh % v % norm = 0\n" i c
									vTan = NormArray[c]
								)
								else
								(
									--if i == 13 do format "v % norm/uv\n" c
									vTan = Normalize( vPos/uvw.y)
								)
								vTan *= 127.0; vTan += 127

								w_array = skinWeightCache[c]
								if w_array == undefined do w_array = #()
								bc = w_array.count
															
								WriteShort nf vPos.x; WriteShort nf vPos.y; WriteShort nf vPos.z
								WriteShort nf 32767		-- always 7FFF
								
								-- get bone map id from this mesh
								bg_id = NewMeshInfo[i][14]  + 1  
								--if i==73 do format " v % bone % [%] % % % % % % % %\n" c bg_id bc b1 b2 b3 b4 w1 w2 w3 w4
								
								w1=w2=w3=w4=0.0
								bi1=bi2=bi3=bi4=0
								
								if (bc > 0 and w_array[1][1] >0 ) then ( bi1 = BoneLUT[bg_id][w_array[1][2]]  - 1; w1= w_array[1][1])
								if (bc > 1 and w_array[2][1] >0 ) then ( bi2 = BoneLUT[bg_id][w_array[2][2]]  - 1; w2= w_array[2][1])
								if (bc > 2 and w_array[3][1] >0 ) then ( bi3 = BoneLUT[bg_id][w_array[3][2]]  - 1; w3= w_array[3][1])
								if (bc > 3 and w_array[4][1] >0 ) then ( bi4 = BoneLUT[bg_id][w_array[4][2]]  - 1; w4= w_array[4][1])
								--if i == 7 do format "v % bc % bone [%] % % % % % % % %\n" c bc bg_id bi1 bi2 bi3 bi4 w1 w2 w3 w4 
								WriteByte nf bi1
								WriteByte nf bi2
								WriteByte nf bi3
								WriteByte nf bi4
							   	--format " v % % % % % % % % % total %\n" c bi1 bi2 bi3 bi4 w1 w2 w3 w4 (w1+w2+w3+w4)
								if RE5_ShouldUseExportVerboseDebug() do
								(     						
									format "mesh % v % bc % % % % % % % % total %" i c bc bi1 bi2 bi3 bi4 w1 w2 w3 w4 (w1+w2+w3+w4)
									for j = 1 to bc do
									(
									bb = w_array[j][2]
									ww = w_array[j][1]
									format "% (%,%)" j bb ww
									)										
									format "\n"
								)
								-- make sure all weight sum up to 255 exactly		

								wt = w1+w2+w3+w4
								wt = 255.0/wt
								w1 = (w1*wt +0.5 ) as integer
								w2 = (w2*wt +0.5 ) as integer
								w3 = (w3*wt +0.5 ) as integer
								w4 = (w4*wt +0.5 ) as integer
								
								adj = 255 - (w1+w2+w3+w4)
								w1 += adj
								--if i == 29 do format " v % % % % % % % % %\n" c bi1 bi2 bi3 bi4 w1 w2 w3 w4
								
								--format " v % % % % % % % % % total %\n" c bi1 bi2 bi3 bi4 w1 w2 w3 w4 (w1+w2+w3+w4)
								--) else format " v % % % % % % % % % total %\n" c bi1 bi2 bi3 bi4 w1 w2 w3 w4 (w1+w2+w3+w4)
								
								WriteByte nf w1
								WriteByte nf w2
								WriteByte nf w3
								WriteByte nf w4
								
								WriteByte nf vNorm.x; WriteByte nf vNorm.y; WriteByte nf vNorm.z; WriteByte nf 255
								WriteByte nf vTan.x; WriteByte nf vTan.y; WriteByte nf vTan.z; WriteByte nf 255
								--WriteByte nf 0;WriteByte nf 0;WriteByte nf 0;WriteByte nf 0
								--WriteByte nf 0;WriteByte nf 0;WriteByte nf 0;WriteByte nf 0
								
					
								--format " % % \n" vNorm vTan
								--uvw.x =0.0; uvw.y = 1.0
								if uvw.x == -131008.0 and uvw.y == -131008.0 or  uvw.x > 65000 or uvw.y > 65000 then
								(  --handle invalid uv
									WriteShort nf (0xffff)
									WriteShort nf (0xffff)											
								)
								else(				
								--format "uvw x % y %\n" uvw.x uvw.y
								u1 = FShort uvw.x
								v1 = FShort uvw.y
								--if i == 13 do format "v % uv % %\n" c u1 v1
									
								WriteShort nf (u1)
								WriteShort nf (v1)
								)
								WriteShort nf (0xffff)
								WriteShort nf (0xffff)		
								--format "vPos %\n" vPos
								--for t=1 to 3 do WriteLong nf 0 --pidding													
							)	
						)
						
					)
					NewMeshInfo[i][9] = (ftell nf) - new_ptr_Vertex --����ڶ����ַ��ƫ������С
					
				)
 				--print NewMeshInfo

                --if (BoneCount == 0) do  -- keep second vertex array
                --(
                --    OrigVertex2 = ftell f
				--	vertex2_size = OrgPtr_triangle - OrigVertex2
                --    for  i = 1 to OrgVertexSize2  do
                --    (
                --        temp = ReadByte f #unsigned
                --        WriteByte nf temp
                --    )
                --)


                NewVertex2 = ftell nf   
                
				--�޸�Mesh header
				--fseek nf ptr_Mesh #seek_set 
				fseek nf new_ptr_Mesh #seek_set 
				local vertStart =0
				local faceStart =0
				local vmin =0
				local vmax =0
				local svc = 0
				local svptr = 0	--ʹ����ͬ��ƫ����
                local svptr2 = 0 --   extended vertex base offset
                local cache_vbase2 = 0
                local vertIndexBase = 0 -- vertex index base for rebase start/end vertex indices ( keeps them < 65535)   
                local vertEnd  -- end vertex index
                local vIndexReset = false

				for i=1 to MeshCount do
				(					                    
					fseek nf 14 #seek_cur    -- forward to  vertEnd location
                    vIndexReset = false                        
					if NewMeshInfo[i][23] == true then
					(
						Writeshort nf 0
						Writelong nf 0
						Writelong nf 0
						if (BoneCount > 0 ) then
							fseek nf 4 #seek_cur
						else
							WriteLong nf 0
						Writelong nf faceStart
						if (BoneCount == 0) then
						(
							fseek nf 4 #seek_cur
							WriteLong nf 0
							fseek nf 2 #seek_cur
							WriteShort nf 0
							fseek nf 8 #seek_cur
						)
						else
							fseek nf 20 #seek_cur
						NewMeshInfo[i][12] = 0
						NewMeshInfo[i][19] = 0
						NewMeshInfo[i][20] = 0
						continue
					)
					if NewMeshInfo[i][8] == 0 then	--��� mesh �Ƿ�ʹ�ö���ƫ���� �������� lod ���� ???
					(	
                        vertEnd = (svc+NewMeshInfo[i][4] - 1)
                        if (vertEnd > 65535)  do  -- vert end index excess unsigned short range
                        (
                            vertIndexBase += svc    -- increase index base and set start index back to 0
                            svc = 0    
                            vIndexReset = true
                        )                    
						Writeshort nf (svc+NewMeshInfo[i][4] - 1)
						Writelong nf svc				-- vertBase  is 0, just set  vertStart
						NewMeshInfo[i][12] = svc
						Writelong nf 0
                        NewMeshInfo[i][20] = 0    -- vertBase                       
						svc += NewMeshInfo[i][4]  -- update vertStart with vertCount
					)else
					(
						vptr = NewMeshInfo[i-1][9]     -- end offset+1 of last mesh, or begining offset of this mesh
						
						if NewMeshInfo[i][8] == NewMeshInfo[i-1][8] then   -- vertBase hasn't change
						(
                            svc += NewMeshInfo[i-1][4]    -- again just accumulate vertStart
                            vertEnd = (svc+NewMeshInfo[i][4] - 1)
                            if (vertEnd > 65535)  do -- vert end index exceed unsigned short range
                            (
                                vertIndexBase += svc    -- increase index base and set start index back to 0
                                svc = 0
                                vIndexReset = true
                            )                            
							Writeshort nf (svc+NewMeshInfo[i][4] - 1)
							Writelong nf svc
							NewMeshInfo[i][12] = svc
							Writelong nf svptr               -- update vertBase with a current base value
                            NewMeshInfo[i][20] = svptr    
						)else
						(                            
                            svc = 0					-- vertBase change, reset vertStart and set new Base
                            vIndexReset = true
							Writeshort nf (svc+NewMeshInfo[i][4] - 1)
							Writelong nf 0
							NewMeshInfo[i][12] = 0
							Writelong nf vptr		-- set a new base 
                            NewMeshInfo[i][20] = vptr
							svptr = vptr		    -- save a copy and make this base current                         
						)												
					)
                    NewMeshInfo[i][19] = NewMeshInfo[i][20]/32 + NewMeshInfo[i][12] + vertIndexBase   -- new absolute vertex start
                    
                    if (BoneCount > 0 ) then
                        fseek nf 4 #seek_cur
                    else
                    (
                        if vIndexReset == true  do      -- if we have a vertex index reset. update extended vertex base.
                            cache_vbase2 = svptr2
                                                               
                        WriteLong nf cache_vbase2;
                        if ((NewMeshInfo[i][1]==true and (execute SelectMeshInfo[NewMeshInfo[i][6]][3])==0x04) or 
                            (NewMeshInfo[i][1]==false and NewMeshInfo[i][2] == 0x04)) do -- this stage mesh use extended vertex section
                            svptr2 += (NewMeshInfo[i][4] * 4) -- increase byte offset, total extended vertex section size
                    )
					
					Writelong nf faceStart
					if NewMeshInfo[i][1] == false then
                        faceStart += NewMeshInfo[i][13]      -- NewMeshInfo[i][5]	-- face list��ʼ
					else
                        faceStart += NewMeshInfo[i][16]   -- new mesh index with degenerate tri
                    
                    if (BoneCount == 0) then  -- stage mesh vertex index base need to be updated
                    (
                           fseek nf 4 #seek_cur   -- skip faceCount
                           WriteLong nf vertIndexBase  -- write new vertex index base
                           fseek nf 2 #seek_cur
                           WriteShort nf NewMeshInfo[i][12]       -- write extended vertex start index                                                    
                           fseek nf 8 #seek_cur     -- leave the rest
                           
                    )
                    else
                        fseek nf 20 #seek_cur    -- leave the rest
					
					--if NewMeshInfo[i][7] == 0 then	--��� mesh �Ķ����ۼ�����
					--(
					--	vmin = 0
					--	Writeshort nf vmin
					--	vmax = vmin + NewMeshInfo[i][4] - 1
					--	Writeshort nf vmax	
					--	vmin += NewMeshInfo[i][4]  						
					--)else
					--(
					--	Writeshort nf vmin
					--	vmax = vmin + NewMeshInfo[i][4] - 1
					--	Writeshort nf vmax							
					--	vmin += NewMeshInfo[i][4]  		
					--)					
					--fseek nf 4 #seek_cur
				)
                
                
				fseek nf NewVertex2 #seek_set  -- right after vertex section end. extended vertex data start here
                				
                if BoneCount == 0 do  -- Only preserve extended vertex data for stage object
                (
                    fseek f ptr_vertex2 #seek_set -- beginning of extend vertex data
                    
                    for i=1 to MeshCount do
                    (					
                         if NewMeshInfo[i][1] then -- this mesh is modified
                         (
                            if NewMeshInfo[i][2] == 0x04 do -- and original vertex has extended data (ambient uv)
                                 fseek f (NewMeshInfo[i][10]/ 8 ) #seek_cur   -- skip old data , NewMeshInfo[i][10] is 32*OrigVertexCount, we weed 4*OrigVertexCount
                         
                			si = NewMeshInfo[i][6]
                            if (execute SelectMeshInfo[si][3]) == 0x04 do  -- new mesh has extended data
                            (
                                matid = SelectMeshInfo2[si][1]
                                hasAmbMap =  MatArray[matid+1].hasAmbMap
                                                                                            
                                local extMeshCache = SelectMeshCache[si]
                                local extUV1 = extMeshCache[2]
                                for v = 1 to  NewMeshInfo[i][4] do
                                 (                          
                                    if hasAmbMap == false then                                 
                                        WriteLong nf 0xffffffff
                                    else
                                    (                                        
                                        uvw = extUV1[v] -- assume ambient uv is same as diffuse map
                                        uvw.y = 1.0 - uvw.y 
                                        u1 = FShort uvw.x
                                        v1 = FShort uvw.y
                                        WriteShort nf (u1)
                                        WriteShort nf (v1)
                                    )
                                 )
                                
                                    
                            )
                         )                         
                         else
                         (
                             if NewMeshInfo[i][2] == 0x04 do   -- has extended data,just transfer as-is
                             (
                                 
                                 for v = 1 to NewMeshInfo[i][4] do
                                 (
                                    temp = ReadLong f #unsigned
                                    WriteLong nf temp
                                 )
                             )
                         )
                          
                    )
                )
                
				--Face
				PtrFace = ftell nf	--�õ� face ptr
				RE5_SetProgress 76 (RE5_UIStr "写入面" "Write faces")
                                                
				fseek f OrgPtr_triangle #seek_set
				for i=1 to MeshCount do
				(
					if i == 1 or i == MeshCount or (mod i 16) == 0 do RE5_SetProgress (76 + ((i as float / MeshCount) * 18.0)) (RE5_UIStr ("写入面 " + (i as string) + "/" + (MeshCount as string)) ("Write faces " + (i as string) + "/" + (MeshCount as string)))
					fc = NewMeshInfo[i][5]
					if NewMeshInfo[i][23] == true then
					(
						local skipFaceIndexCount = NewMeshInfo[i][13]
						if skipFaceIndexCount == undefined do skipFaceIndexCount = 0
						if skipFaceIndexCount > 0 do fseek f (skipFaceIndexCount * 2) #seek_cur
						continue
					)
					
					--format "m % : old vstart % new vstart % diff %\n" i NewMeshInfo[i][17] NewMeshInfo[i][12] (NewMeshInfo[i][12] - NewMeshInfo[i][17])  
					local LastTemp	
                    --if (i == 80 ) do format " pos %\n" (ftell f)
					if NewMeshInfo[i][1] == false then	--����Ҫ�޸���ֱ�Ӹ���
					(				   						
						ofc = NewMeshInfo[i][13]      -- this is the real original face index count including degenerate tris,  
													  -- NewMeshInfo[i][5] contains visible tris 						
						for c=1 to ofc do
						(
							ReadTemp = readshort f #unsigned
							--if  ( i > 1 ) and ( c == 1 ) and  ( NewMeshInfo[i-1][1] == true ) do 
							   --( Writeshort nf ReadTemp; format " last mesh is modify %\n" i )p 
							if ReadTemp == undefined then	
                            (
                                break
								ReadTemp = LastTemp
                                if RE5_ShouldUseExportVerboseDebug() do format " end of file\n"
                                ) 
							else
							(						
								--NewMeshInfo[i][17] = OrgMeshInfo.vertStart
								--NewMeshInfo[i][12] = new vertStart
								ReadTemp = ReadTemp - NewMeshInfo[i][17] + NewMeshInfo[i][12] -- adjust faceindex for new vertStart
								LastTemp = ReadTemp
							)
                            
							--if ( i == MeshCount) do format " face % % %\n" c ReadTemp LastTemp
							Writeshort nf ReadTemp
							
						)
					)else
					(
						wfc = NewMeshInfo[i][13]*2    -- NewMeshInfo[i][11]*2
						
						fseek f wfc #seek_cur	--����ԭʼmesh face short
						--print wfc
						si = NewMeshInfo[i][6]
						OutMesh = SelectMeshInfo[si][1]	--��Ӧѡ��� Mesh
						local faceCache = undefined
						if RE5_IsExportOptimizationEnabled RE5ExportReuseCachedFaceArrays and SelectMeshCache[si] != undefined then faceCache = SelectMeshCache[si][3]
						if faceCache == undefined then faceCache = RE5_TryGetBulkFaces OutMesh
						fvc = fc /3
						--print fvc
						--local TriList =  NewMeshInfo[i][17]
						--format "TriList size %\n" TriList.count
						local fv 
						--if i == 33 do format "vert start % len % real len %\n" NewMeshInfo[i][12] fvc fc
						for c=1 to fvc do
						(
							fv = faceCache[c]
							Writeshort nf (fv.x - 1 + NewMeshInfo[i][12])
							Writeshort nf (fv.y - 1 + NewMeshInfo[i][12])
							Writeshort nf (fv.z - 1 + NewMeshInfo[i][12])
							--format " %" fv
						)
						--format "\n"
-- 						print NewMeshInfo[i][4]
											
					)
				)
				
				--00 0000 �ж��ļ���С
				EndSize = ftell nf
				if EndSize > int(EndSize/4)*4 then 
				(
					Writeshort nf 0
					EndSize += 2
				)
				--Writelong nf 0				
				
				--�޸��ļ�ͷ
				local avc =0
				local afc =0
				local avs =0
				for i=1 to MeshCount do
				(
                    --format "mesh % afc %\n" i afc
					avc += NewMeshInfo[i][4]
                    --if NewMeshInfo[i][1] == true then
                    --    afc += NewMeshInfo[i][5] -- tri list size
                    --else
                    --    afc += NewMeshInfo[i][13] -- tri stripe size  
					avs += NewMeshInfo[i][4]*NewMeshInfo[i][3]
				)
				afc = (EndSize - PtrFace) /2
				RE5_SetProgress 96 (RE5_UIStr "回填头信息" "Finalize header")
				
				fseek nf 12 #seek_set
				Writelong nf avc	--vertex count
				Writelong nf afc	--face count
				fseek nf 24 #seek_set
				Writelong nf avs	--size of all vertex 
				if BoneCount > 0  then
                    Writelong nf 0	--  wipe out size of second vertex array
                else
                    WriteLong nf svptr2
				fseek nf 40 #seek_set
				if BoneCount >  0 then  
					Writelong nf (NextBoneMapIndex - 1)
				fseek nf 48 #seek_set
				Writelong nf new_ptr_Group
				Writelong nf new_ptr_Texture
				Writelong nf new_ptr_Mesh
				Writelong nf new_ptr_Vertex				
				if BoneCount > 0 then 
					Writelong nf 0         -- no offset for second vertex array
				else
					WriteLong nf NewVertex2
				Writelong nf PtrFace	--face ��ַ �����ַ����
				--Writelong nf EndSize	--�ļ���С
							
				if BoundChange == true do  -- if bound grow update header
				(
                    if RE5_ShouldUseExportVerboseDebug() do format "bound change = true\n"
					cx  = (maxx-minx)/2.0 + minx
					cy  = (maxy-miny)/2.0 + miny
					cz  = (maxz-minz)/2.0 + minz
					fseek nf 80 #seek_set
					WriteFloat nf cx   -- center
					WriteFloat nf cy
					WriteFloat nf cz
					fseek nf 4 #seek_cur
					WriteFloat nf minx
					WriteFloat nf miny
					WriteFloat nf minz
					fseek nf 4 #seek_cur
					WriteFloat nf maxx
					WriteFloat nf maxy
					WriteFloat nf maxz
                    if RE5_ShouldUseExportVerboseDebug() do format "change center % % % min % % % max % % %\n" cx cy cz minx miny minz maxx maxy maxz
				)
				fclose f
				fclose nf
				RE5_SetProgress 100 (RE5_UIStr "完成" "Complete")
				messageBox (RE5_UIStr "完成！\n\n请使用 RE5TriStrip 将 .NewMOD 转换为 .mod" "Complete !\n\nUse RE5TriStrip to convert .NewMOD to .mod")
			)
		) else 
		(
			RE5_SetProgress 0 (RE5_UIStr "已中止" "Aborted")
			if selection.count == 0 do (messagebox (RE5_UIStr "操作已中止\n\n请先选择一个 Mesh！" "ACTION ABORTED\n\nSelect a mesh first!"))
		)
	)
	
	on btn7 pressed do (
	if edt4.text!=undefined AND edt4.text!="" do (
		for i = 1 to selection.count do (
			sName = filterString selection[i].name "_"
			if sName[1]=="Mesh" do (
-- 	SelectMeshInfo[i] = #(selection[i],sName[2],sName[3],i)		--#(Mesh, MeshIndex, VertexType)
			mshHdr_matid = mshHdr_grp = mshHdr_mde = mshHdr_lod = 0
			if sName.count == 7 do (
				mshHdr_matid = execute ((filterString sName[5] "x")[2])
				mshHdr_grp = execute ((filterString sName[6] "x")[2])
				mshHdr_mde = execute ((filterString sName[7] "x")[2])
				mshHdr_lod = execute ((filterString sName[4] "x")[2])
					)
			case rdo2.state of (
			1:(mshHdr_lod = execute edt4.text)
			2:(mshHdr_matid = execute edt4.text)
			3:(mshHdr_grp = execute edt4.text)
			4:(mshHdr_mde = execute edt4.text)
			)
			selection[i].name = "Mesh_"+ sName[2] +"_"+ sName[3] +"_LODx"+ mshHdr_lod as string + "_MatIDx" + mshHdr_matid as string + "_Groupx" + mshHdr_grp as string + "_DisplayModex" + mshHdr_mde as string
				)
		)
		messagebox (RE5_UIStr "完成。" "Done.")
		)
	)
)-- rollout end
RE5_InitRuntimeProfile()
RE5DialogSize = RE5_UIGetDialogSizeForCurrentLayout()
createDialog Re5ModTool RE5DialogSize.x RE5DialogSize.y
