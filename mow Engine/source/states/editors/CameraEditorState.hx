package states.editors; // <-- ปรับ package ให้ตรงกับโฟลเดอร์ที่คุณวางไฟล์

import flixel.FlxG;
import backend.MusicBeatState;
import backend.CacheSystem;
import backend.Mods;
import flixel.sound.FlxSound;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import objects.Character;
import objects.Note;
import objects.VideoSprite;
import backend.StageData;
import backend.Song;
import haxe.ds.ObjectMap;
import mikolka.stages.EventLoader;
import mikolka.funkin.custom.NativeFileSystem;
import states.PlayState;
import states.editors.content.FileDialogHandler;
import states.editors.content.PsychJsonPrinter;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import backend.ui.PsychUIInputText;
import haxe.Json;
import openfl.geom.Rectangle;
import openfl.geom.Matrix;
import openfl.geom.ColorTransform;
import openfl.display.BitmapData;
import openfl.utils.Assets;
import openfl.net.FileReference;
import openfl.net.FileFilter;
import flash.media.Sound;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if LUA_ALLOWED
import psychlua.FunkinLua;
#end
#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
#end

/**
 * Live Camera Editor (Focus / Zoom timeline)
 *
 * - ใช้ PlayState จริงเป็นฉากและระบบเล่นเพลง แล้ววาง UI สำหรับแก้กล้องทับไว้
 * - ไม่มี stage, character, script หรือ preview audio ชุดที่สอง
 * - Preview และเกมใช้ event, animation, audio และ camera lifecycle ชุดเดียวกัน
 * - Event เก็บเป็น JSON (camera_events.json) ใช้กับระบบกล้องใน PlayState
 *
 * ปุ่มลัด
 *   ลากบน timeline : scrub; ลาก event เพื่อย้าย / ลากขอบขวาปรับ duration
 *   คลิกขวาบน track : เพิ่ม event ตรงตำแหน่งเมาส์ (เลเยอร์ที่คลิก; Focus อยู่บน, Zoom อยู่ล่าง)
 *   ปุ่ม + / - ข้างชื่อ track : เพิ่ม / ลบเลเยอร์ (ลากแนวตั้งเพื่อย้าย key ข้ามเลเยอร์)
 *   ปุ่มกลางลาก : pan timeline หรือฉาก | Wheel: zoom | Ctrl/Shift+Wheel: zoom timeline
 *   ลากใน Preview   : ย้ายจุดโฟกัสของ Focus event ที่เลือก
 *   Del             : ลบ event       | Ctrl+Z / Ctrl+Y : Undo / Redo
 *   Space           : Play / Pause   | Ctrl+S : Save    | F5 : PlayTest | Esc : Exit
 *   Arrows (Shift=50): ขยับ x/y      | Q / E : zoom -/+ | Z / X : duration -/+
 *   C : เปลี่ยน ease                 | T : เปลี่ยน target (custom/BF/Opp/GF)
 *   Enter / F2 / ดับเบิลคลิก key : เปิดหน้าต่างแก้ key (พิมพ์ตัวเลขเอง, dropdown, กราฟ Ease + ตัวอย่างการขยับ, Warp / Release)
 *   V : Relative View | B : Extended Bounds | P : Passepartout | F : Fit View
 */
typedef CamEvent =
{
	var time:Float; // ms
	var track:String; // "focus" | "zoom" | "tilt"
	var x:Float; // focus: พิกัด world (target=-1) หรือ offset จากตัวละคร
	var y:Float;
	var zoom:Float;
	var duration:Float; // ms
	var ease:String; // ชื่อใน FlxEase
	var target:Int; // -1 = custom, 0 = BF, 1 = Opponent, 2 = GF
	@:optional var layer:Int; // เลเยอร์ภายใน track (0 = บนสุด) ใช้แยก key ที่ซ้อนเวลากัน
	@:optional var angle:Float; // tilt: มุมเอียงกล้อง (องศา, + = หมุนตามเข็ม) ใช้กับ track "tilt" เท่านั้น
	@:optional var autoRelease:Bool; // focus: ปล่อย forced camera เมื่อ Duration จบโดยอัตโนมัติ
	@:optional var hudZoom:Float; // kick: preserve Add Camera Zoom Value 2 independently when available
}

private typedef PreviewNote =
{
	var time:Float;
	var who:Int; // 0=BF, 1=Opponent, 2=GF
	var lane:Int;
	var playerSide:Bool;
	var animation:String;
	var sustain:Float;
	var noteType:String;
}

private typedef PreviewChartEvent =
{
	var time:Float;
	var strumTime:Float;
	var name:String;
	var value1:String;
	var value2:String;
	var rawRow:Array<Dynamic>;
	var rawSubEvent:Array<Dynamic>;
}

private typedef PreviewBopEvent =
{
	var time:Float;
	var frequency:Float;
	var multiplier:Float;
}

private typedef PreviewZoomDecayEvent =
{
	var time:Float;
	var endTime:Float;
}

private typedef ChartCameraLink =
{
	var camera:CamEvent;
	var source:PreviewChartEvent;
	var component:String;
}

private typedef CameraEventListEntry =
{
	var time:Float;
	var name:String;
	var camera:CamEvent;
	var source:PreviewChartEvent;
	var component:String;
}

private typedef ChartEventDefinition =
{
	var name:String;
	var description:String;
}

private typedef CameraEditorMenuItem =
{
	var label:String;
	var action:Void->Void;
	@:optional var enabled:Bool;
}

private typedef CameraEditorMenu =
{
	var name:String;
	var items:Array<CameraEditorMenuItem>;
}

private typedef KwButton =
{
	var id:String;
	var label:String;
	var x:Float;
	var y:Float;
	var w:Float;
	var h:Float;
	var active:Bool;
}

private class CamCmd
{
	public var run:Void->Void;
	public var undo:Void->Void;
	public var ev:CamEvent = null; // event ที่คำสั่งนี้แตะ ใช้เลือกกลับหลัง Undo / Redo
	public var oldVal:CamEvent = null; // ค่าเดิมก่อนแก้ ใช้รวมการแก้ต่อเนื่องเป็นสเต็ปเดียว
	public var stamp:Float = 0;

	public function new(run:Void->Void, undo:Void->Void)
	{
		this.run = run;
		this.undo = undo;
	}
}

private enum DragMode
{
	None;
	Move;
	Resize;
	Preview;
	Seek;
	PanTimeline;
	PanPreview;
	Marquee;
	ZoomSlide;
	VScroll;
	TimelineResize;
	TimelineTopResize;
	PropSlide;
}

class CameraEditorState extends PlayState
{
	// Use local helpers instead of StringTools: this fork defines its own
	// mikolka.funkin.utils.StringTools class without the standard methods.
	static inline function camStartsWith(value:String, prefix:String):Bool
		return value != null && prefix != null && value.length >= prefix.length && value.substr(0, prefix.length) == prefix;

	static inline function camContains(value:String, part:String):Bool
		return value != null && part != null && value.indexOf(part) >= 0;

	static inline function camEndsWith(value:String, suffix:String):Bool
		return value != null && suffix != null && value.length >= suffix.length && value.substr(value.length - suffix.length) == suffix;

	static inline function isAutoReleaseToken(value:String):Bool
	{
		if (value == null) return false;
		var token = value.trim().toLowerCase();
		return token == 'auto_release' || token == 'auto-release' || token == 'autorelease';
	}

	static function hasAutoReleaseMarker(value:String):Bool
	{
		if (value == null || value.length == 0) return false;
		for (part in value.split(',')) if (isAutoReleaseToken(part)) return true;
		return false;
	}

	static function timingWithAutoRelease(value:String, enabled:Bool):String
	{
		var parts:Array<String> = [];
		if (value != null && value.length > 0)
			for (part in value.split(',')) if (!isAutoReleaseToken(part)) parts.push(part);
		if (enabled) parts.push('AUTO_RELEASE');
		return parts.join(',');
	}

	static inline function setTextIfChanged(target:FlxText, value:String):Void
	{
		if (target != null && target.text != value) target.text = value;
	}
	// ---------- ค่าที่ควรให้ PlayState/Stage เป็นคนใส่ก่อนเปิด editor ----------
	public static var charPos:Array<Array<Float>> = [[1450, 600], [400, 600], [900, 550]]; // BF, Opp, GF
	public static var defaultCam:Array<Float> = [900, 450]; // ตำแหน่งกล้องเริ่มต้น
	public static var defaultZoom:Float = 1.0;
	public static var worldW:Float = 2000;
	public static var worldH:Float = 900;

	// ---------- editor state ----------
	public static var returnToGameplay:Bool = true;
	public static var returnToEditorMenu:Bool = false;
	/** Set only when F5 starts a gameplay test; PlayState consumes it at song end. */
	public static var returnToCameraEditorAfterPlayTest:Bool = false;
	private static var restoreMenuMusicAfterDestroy:Bool = false;
	/** Events imported from another song JSON, applied after the live state is rebuilt. */
	public static var pendingImportedEvents:Dynamic = null;
	private static var menuChartPicker:FileDialogHandler;
	private static var editorMenuMusic:FlxSound;
	private static var editorMenuMusicWasPlaying:Bool = false;
	private static var editorMenuMusicTime:Float = 0;
	private static var editorMenuMusicVolume:Float = 1;
	private static var editorMenuMusicCaptured:Bool = false;
	var previewCamera:FlxCamera;
	var editorUICamera:FlxCamera;
	/** Hide cameras other than the gameplay viewport and editor UI to prevent stray script cameras/fades blacking out the preview. */
	var hideOtherCameras:Bool = true;
	var originalCameraVisibility:ObjectMap<FlxCamera, Bool> = new ObjectMap();
	var originalGameCameraX:Float = 0;
	var originalGameCameraY:Float = 0;
	var originalGameCameraWidth:Int = 0;
	var originalGameCameraHeight:Int = 0;
	var previewInitTimer:FlxTimer;
	var soundsBeforeEditor:Array<FlxSound> = [];
	var previewCharacters:Array<Character> = [null, null, null]; // BF, Opponent, GF
	var previewNotes:Array<PreviewNote> = [];
	/** Prevent the preview-only note simulator from firing hit callbacks for notes the botplay must avoid. */
	var blockedPreviewNoteKeys:Map<String, Bool> = new Map();
	var firstChartNoteTime:Float = Math.POSITIVE_INFINITY;
	var chartCameraEvents:Array<CamEvent> = [];
	var sortedCameraEvents:Array<CamEvent> = [];
	var focusCameraEvents:Array<CamEvent> = [];
	var zoomCameraEvents:Array<CamEvent> = [];
	var tiltCameraEvents:Array<CamEvent> = [];
	var tiltWasOwned:Bool = false; // timeline เคยคุมมุมกล้อง (Tilt) อยู่ ใช้คืนมุมเป็น 0 เมื่อ playhead ถอยกลับก่อน key แรก
	var zoomKickEvents:Array<CamEvent> = [];
	var focusReleaseEvents:Array<CamEvent> = [];
	var previewBopEvents:Array<PreviewBopEvent> = [];
	var previewZoomDecayEvents:Array<PreviewZoomDecayEvent> = [];
	var previewBopScratch:{frequency:Float, multiplier:Float} = {frequency: 4, multiplier: 1};
	var sectionCameraTargets:Array<{time:Float, x:Float, y:Float}> = [];
	var cameraEventCacheDirty:Bool = true;
	var previewChartEvents:Array<PreviewChartEvent> = [];
	var cameraEventList:Array<CameraEventListEntry> = [];
	var cameraEventListDirty:Bool = true;
	var cameraEventListScroll:Int = 0;
	var chartCameraLinks:Array<ChartCameraLink> = [];
	var selectedChartSource:PreviewChartEvent = null;
	var selectedChartComponent:String = null;
	var availableChartEvents:Array<ChartEventDefinition> = [];
	var previewNoteCursor:Int = -1;
	var scriptNoteCursor:Int = 0;
	var previewChartEventCursor:Int = 0;
	var previewActionUntil:Array<Float> = [-1, -1, -1];
	var previewSinging:Array<Bool> = [false, false, false];
	var lastPreviewTime:Float = -1;
	/** ตำแหน่งเพลงที่ซิงก์ท่าตัวละครไว้ล่าสุด และธงบังคับให้สร้างท่าใหม่ (เช่นหลังโหลด chart) */
	var animSyncPos:Float = -1;
	var animSyncDirty:Bool = true;
	/** กรอ/ย้อนแล้วต้องรีเซ็ตสถานะอีเวนต์ + Lua แล้วเล่นอีเวนต์ซ้ำจนถึงตำแหน่งใหม่ (ทำหลังปล่อยเมาส์) */
	var eventReplayPending:Bool = false;
	/** มุมหมุนจริงของกล้องเกม (จาก event/lua) ใช้หมุนกรอบ VCam ตอน Free View */
	var vcamAngle:Float = 0;
	var realCamAngle:Float = 0;
	var appliedCamScrollX:Float = 0;
	var appliedCamScrollY:Float = 0;
	var appliedCamZoom:Float = 1;
	var appliedCamAngle:Float = 0;
	var needInitialFit:Bool = true;
	/** ปิด Lua ของเพลงที่เปิดอยู่เท่านั้น (data/<เพลง>/*.lua) ส่วน scripts/, custom_events, notetypes, stages, characters ยังทำงานตามเดิม */
	public static var disableSongLua:Bool = false;
	#if LUA_ALLOWED
	var stashedSongLuas:Array<FunkinLua> = [];
	#end
	var lastBeatTick:Int = -1;
	var stageName:String = '';
	var stageLoadError:String = '';
	var stageCameraSpeed:Float = 1;
	var stageHost:PlayState = null; // aliases this live PlayState for timeline evaluation helpers
	var scriptCameraFollowOverride:Bool = false;
	var scriptCameraZoomOverride:Bool = false;
	var scriptCameraForced:Bool = false;
	var lastSyncedFollowX:Float = Math.NaN;
	var lastSyncedFollowY:Float = Math.NaN;
	var lastSyncedZoom:Float = Math.NaN;
	var lastKnownMemberCount:Int = 0; // track sprites scripts add directly to the active Editor state
	var dynamicPreviewMembers:Array<FlxBasic> = [];
	var dynamicPreviewGroupChildren:Array<{parent:FlxBasic, child:FlxBasic}> = [];
	var previewGroupMemberBaselines:ObjectMap<FlxBasic, Array<FlxBasic>> = new ObjectMap();
	var previewStageUpdateArgs:Array<Dynamic> = [0.0];
	var stageTreeCameraSizes:Array<{stage:Dynamic, size:Int}> = [];
	var stageCameraOffsets:Array<Array<Float>> = [[0, 0], [0, 0], [0, 0]];
	var viewCenterX:Float = 900;
	var viewCenterY:Float = 450;
	var viewZoom:Float = 1;
	var relativeView:Bool = true;
	var extendedBounds:Bool = false;
	var passepartout:Bool = false;
	var showCameraFrame:Bool = true;
	/** มุมมอง editor ถูกใส่ลงกล้องแค่ช่วงวาด แล้วคืนค่าจริงหลัง render เสร็จ (ดู draw / restoreRealCameraView) */
	var editorViewApplied:Bool = false;
	var editorViewHooked:Bool = false;
	var realCamScrollX:Float = 0;
	var realCamScrollY:Float = 0;
	var realCamZoom:Float = 1;
	var previewPanMouseX:Float = 0;
	var previewPanMouseY:Float = 0;
	var previewPanOriginX:Float = 0;
	var previewPanOriginY:Float = 0;
	var timelinePanMouseX:Float = 0;
	var timelinePanOriginMs:Float = 0;
	var lastScriptStep:Int = -1;
	var lastScriptBeat:Int = -1;
	var lastScriptSection:Int = -1;
	var previewResourceSweepAccumulator:Float = 0;
	var previewCacheSweepAccumulator:Float = 0;
	var previewMemoryGcAccumulator:Float = 0;
	var easeCache:Map<String, Float->Float> = new Map();
	var chartCameraPointScratch:{x:Float, y:Float} = {x: 0, y: 0};
	var cameraEvalScratch:{x:Float, y:Float, zoom:Float} = {x: 0, y: 0, zoom: 1};
	var cameraActualScratch:{x:Float, y:Float, zoom:Float} = {x: 0, y: 0, zoom: 1};
	/** VCam: ท่า (ตำแหน่ง + zoom) ของกล้องเกมจริงที่ผู้เล่นจะเห็น ใช้วาดกรอบ ไม่ขึ้นกับมุมมองของ editor */
	var vcamPose:{x:Float, y:Float, zoom:Float} = {x: 0, y: 0, zoom: 1};
	/** เป้าหมายที่ timeline สั่งกล้องจริงตอนเล่น (vcamPose คือกล้องจริงที่กำลังเคลื่อนตามไป) */
	var vcamExpected:{x:Float, y:Float, zoom:Float} = {x: 0, y: 0, zoom: 1};
	/** true = ตอนนี้ timeline (focus / zoom event) เป็นเจ้าของกล้องอยู่ */
	var vcamTimelineOwned:Bool = false;
	var vcamWasFocusOwned:Bool = false;
	var vcamInfoText:FlxText;
	/** Camera-attached FX captured in Free View and composited only inside the VCam bounds. */
	var vcamFxFlashColor:FlxColor = FlxColor.WHITE;
	var vcamFxFadeColor:FlxColor = FlxColor.BLACK;
	var vcamFxFlashAlpha:Float = 0;
	var vcamFxFadeAlpha:Float = 0;
	var vcamFxShakeX:Float = 0;
	var vcamFxShakeY:Float = 0;
	var vcamFxRestoreFlashAlpha:Float = 0;
	var vcamFxRestoreFadeAlpha:Float = 0;
	var vcamFxRestoreShakeX:Float = 0;
	var vcamFxRestoreShakeY:Float = 0;
	var vcamFxHadFlashAlpha:Bool = false;
	var vcamFxHadFadeAlpha:Bool = false;
	var vcamFxMuted:Bool = false;
	/** กดหยุดระหว่างเล่น: VCam ค้างที่ตำแหน่ง/ซูมจริง ณ ตอนนั้น (ไม่กระโดดไปค่าที่คำนวณจาก timeline) จนกว่าจะ seek หรือแก้ key */
	var pauseHold:Bool = false;
	var pauseHoldPose:{x:Float, y:Float, zoom:Float} = {x: 0, y: 0, zoom: 1};
	/** วิวพอร์ตจริงของภาพพรีวิว: สัดส่วนเท่าจอเกม พอดีใน PREV_* (จัดกึ่งกลาง) กรอบเทา/กรอบ VCam/เมาส์ใช้ค่านี้ทั้งหมด */
	var pvX:Int = 24;
	var pvY:Int = 40;
	var pvW:Int = 936;
	var pvH:Int = 460;
	var viewportFixNotified:Bool = false;
	var cameraLensScratch:{width:Float, height:Float} = {width: 0, height: 0};
	var cameraFrameScratch:{x:Float, y:Float, width:Float, height:Float} = {x: 0, y: 0, width: 0, height: 0};

	// ---------- layout ----------
	static inline var PREV_X = 24;
	static inline var PREV_Y = 40;
	static inline var PREV_W = 936;
	static inline var PANEL_X = 978;
	static inline var PANEL_W = 286;
	static inline var TL_X = 150;
	static inline var RULER_H = 26;
	static inline var TRACK_H = 45; // ให้แถวที่ 3 โผล่ได้เมื่อขยาย timeline ลงมา
	static inline var VISIBLE_ROWS = 2; // จำนวนแถวเริ่มต้นที่เห็นพร้อมกัน
	static inline var GEN_W = 34; // ความกว้างช่อง General Camera (สั้น ๆ แค่บอกว่ากล้องหันไปหาใคร)
	static inline var SCALE = 0.4; // world -> preview
	static inline var EDGE = 12; // px จับขอบขวา block (ขยายให้จับง่าย)
	static inline var MAX_LAYERS_PER_TRACK = 32;
	// จำนวนเลเยอร์สูงสุดของ Focus และ Zoom อย่างละ track
	static inline var MIN_ROW_H = 17; // ความสูงแถวต่ำสุดเมื่อมีหลายเลเยอร์
	static inline var TL_BOTTOM = 671; // ขอบล่างของแทร็ก; เว้นรางจับ resize 13px ก่อนแถบสถานะ
	static final TIMELINE_FOLLOW_LABELS:Array<String> = ['Realtime', 'Every 4 Steps', 'At Edge', 'Off'];
	static inline var COALESCE_MS = 600; // แก้ event เดิมต่อเนื่องภายในเวลานี้ = undo สเต็ปเดียว

	static final EASES:Array<String> = [
		"linear", "quadOut", "quadInOut", "cubeOut", "cubeInOut", "sineInOut", "expoOut", "backOut", "elasticOut"
	];
	static final TARGET_NAMES:Array<String> = ["custom", "BF", "Opponent", "GF"];
	// ---- Key editor window / drop-downs ----
	static final EASE_BASES:Array<String> = ['linear', 'quad', 'cube', 'quart', 'quint', 'sine', 'expo', 'circ', 'back', 'bounce', 'elastic', 'smoothStep', 'smootherStep'];
	static final EASE_BASE_LABELS:Array<String> = ['Linear', 'Quad', 'Cube', 'Quart', 'Quint', 'Sine', 'Expo', 'Circ', 'Back', 'Bounce', 'Elastic', 'Smooth Step', 'Smoother Step'];
	static final EASE_DIRS:Array<String> = ['In', 'Out', 'InOut'];
	static final EASE_DIR_LABELS:Array<String> = ['In', 'Out', 'In/Out'];
	static final TARGET_ORDER:Array<Int> = [-1, 0, 1, 2, -2]; // -2 = Release (ปล่อยกล้องกลับไปตามปกติ)
	static final TARGET_LABELS:Array<String> = ['Custom (X / Y)', 'BF', 'Opponent', 'GF', 'Release (back to normal)'];
	static inline var KW_W = 640;
	static inline var KW_H = 452;
	static inline var KW_FW = 200; // ความกว้างช่องค่าในหน้าต่าง
	static final MAX_DYNAMIC_PREVIEW_MEMBERS:Int = 128;
	static final MAX_NESTED_DYNAMIC_PREVIEW_MEMBERS:Int = 128;
	static final MAX_PREVIEW_SCRIPT_SOUNDS:Int = 64;
	static final MAX_UNDO_HISTORY:Int = 64;
	static final HELP_TEXT:String = 'Space  Play / Pause                 F5  Play Test\n'
		+ 'Ctrl+S  Save all events to Events   Ctrl+Z / Ctrl+Y  Undo / Redo\n'
		+ 'Esc  Exit editor                    F1  Close this help\n\n'
		+ 'Timeline: drag ruler or empty space to seek; drag a key to move it.\n'
		+ 'Right-click a track to add a camera key; drag its end to change duration.\n'
		+ 'Layers: + / - beside Focus, Zoom and Tilt add or remove layers; drag a key up or down to change layer.\n'
		+ 'Tilt: Edit > Add Tilt Event or right-click the TiltCamera row. Saved as the "Rol cam" chart event (Value 1 = angle, Value 2 = seconds,ease).\n'
		+ 'Preview: drag to move the selected focus; right / middle / Alt+drag pans (switches to Free View).\n'
		+ 'Mouse wheel zooms the preview or timeline; Ctrl/Shift+wheel changes timeline scale.\n'
		+ 'Drag the centered timeline grips to resize; pull the top grip upward to shrink the preview. Use the Follow control beside curStep to change auto-scroll mode.\n\n'
		+ 'V  Relative view      B  Extended bounds      P  Passepartout      F  Fit view\n'
		+ 'Arrows move focus (Shift x10, Alt x0.1)   Q / E zoom (Shift 0.05, Alt 0.001)   Z / X duration   C easing\n'
		+ 'GeneralCamera row: click faded block = take control, right-click = add, 1/2/3 or T = BF/Opp/GF, Delete = remove   Ctrl+wheel / scrollbar = scroll rows';

	// ---------- data ----------
	var events:Array<CamEvent> = [];
	var selected:CamEvent = null;
	var history:Array<CamCmd> = [];
	var redoStack:Array<CamCmd> = [];

	// ---------- autosave / backup ----------
	/** โฟลเดอร์ backup ของตัวเกม (อยู่ข้างตัวเกม ไม่ใช่ใน mod) autosave จะลงที่ BACKUP_DIR/<ชื่อเพลง>/ ปรับที่เดียวตรงนี้ */
	static inline var BACKUP_DIR:String = 'backup/camera_editor';
	static inline var AUTOSAVE_INTERVAL:Float = 60; // วินาที (เซฟเฉพาะตอนมีอะไรเปลี่ยน และไม่เซฟระหว่างเล่น)
	static inline var AUTOSAVE_KEEP:Int = 10; // เก็บไฟล์ backup ล่าสุดกี่ไฟล์ต่อเพลง
	/** event ของ Chart ที่เป็นเรื่องกล้อง: ถือเป็น "กล้อง" ไม่นับเป็น event อื่น */
	static final CAMERA_CHART_EVENT_NAMES:Array<String> = [
		'target camera', 'zoom camera', 'focuscamera', 'focus camera', 'zoomcamera',
		'camera follow pos', 'camera warp pos', 'camera focus xy', 'set camzoom', 'set camera zoom', 'defaultcamzoom', 'camera control',
		'set camera bopping', 'rol cam', 'roll camera', 'add camera zoom'
	];
	/** false = เซฟเฉพาะกล้อง, true = เซฟ event อื่นนอกเหนือกล้องของ Chart รวมไปด้วย (Save / Save As / Autosave ใช้ค่านี้ร่วมกัน) */
	static var saveOtherEvents:Bool = true;
	var autosaveTimer:Float = 0;
	var lastAutosaveJson:String = null;
	var lastDataEventsBackupText:String = null; // เนื้อ events.json ล่าสุดที่สำรองไปแล้ว (กันสำรองซ้ำ แต่สำรองทุกครั้งที่ไฟล์เปลี่ยนก่อนเขียนทับ)
	var backupSerial:Int = 0; // กันชื่อไฟล์ backup ซ้ำกันในวินาทีเดียวกัน (จะได้ไม่ทับกัน)
	var exitBackupDone:Bool = false;
	var dataExportError:String = null;

	// Overwrite confirmation for data/<song>/events.json. This is an in-editor modal so it
	// works in the custom engine without relying on platform-specific native confirm dialogs.
	var saveConfirmOpen:Bool = false;
	var saveConfirmPath:String = '';
	var saveConfirmYesAction:Void->Void = null;
	var saveConfirmX:Float = 0;
	var saveConfirmY:Float = 0;
	var saveConfirmDim:FlxSprite;
	var saveConfirmPanel:FlxSprite;
	var saveConfirmTitle:FlxText;
	var saveConfirmBody:FlxText;
	var saveConfirmYes:FlxText;
	var saveConfirmNo:FlxText;

	// ---------- timeline layers ----------
	var focusLayers:Int = 1;
	var zoomLayers:Int = 1;
	var tiltLayers:Int = 1;
	/** Panel height is user-resizable; row count follows the available height. */
	var timelinePanelHeight:Float = RULER_H + TRACK_H * VISIBLE_ROWS;
	/** Top edge is movable: dragging it upward grows the timeline and compresses the preview area. */
	var timelineTopY:Int = 520;
	var timelineTopResizeMouseY:Float = 0;
	var timelineTopResizeStartY:Float = 520;
	var timelineResizeMouseY:Float = 0;
	var timelineResizeStartHeight:Float = 0;
	static inline var MIN_PREVIEW_PANEL_H:Int = 260;
	static inline var PREVIEW_TIMELINE_GAP:Int = 20;
	/** Cached editor mouse cursors loaded from assets/embed/images/ui. */
	var editorCursorState:String = '';
	var editorOriginalCursor:BitmapData;
	var editorCursorDefault:BitmapData;
	var editorCursorHand:BitmapData;
	var editorCursorHand2:BitmapData;
	var timelineFollowMode:Int = 0; // Realtime / Every 4 Steps / At Edge / Off
	var lastTimelineFollowStep:Int = -1;
	var layerLabels:Array<FlxText> = [];
	var layerButtons:Array<FlxText> = []; // [Focus +, Focus -, Zoom +, Zoom -, Tilt +, Tilt -]
	var dragCreated:Bool = false;
	var multiSel:Array<CamEvent> = [];
	var propLabels:Array<FlxText> = [];
	var propValues:Array<FlxText> = [];
	var propArrows:Array<FlxText> = [];
	var sectionWho:Array<Int> = [];
	var sectionEnds:Array<Float> = [];
	var sectionLabels:Array<FlxText> = [];
	var vScrollGrab:Float = 0;
	var layerScrollY:Float = 0;
	var timelinePanMouseY:Float = 0;
	var timelinePanOriginY:Float = 0;
	var marqueeX0:Float = 0;
	var marqueeY0:Float = 0;
	var marqueeAdd:Bool = false;
	var snapEnabled:Bool = true;
	var clipOn:Bool = false;
	var clipY0:Float = 0;
	var clipY1:Float = 0;
	var dragMulti:Array<CamEvent> = null;
	var dragMultiOld:Array<CamEvent> = null;
	var clipboard:Array<CamEvent> = [];
	var zoomBtnTexts:Array<FlxText> = []; // [-, +, label]

	// ---------- key editor window / drop-down ----------
	var kwOpen:Bool = false;
	var kwAnimT:Float = 0;
	var kwFromX:Float = 0;
	var kwFromY:Float = 0;
	var kwFromZoom:Float = 1;
	var kwFromAngle:Float = 0;
	var kwFromFor:CamEvent = null;
	var kwFromTime:Float = -1;
	var kwLastDuration:Float = 500;
	var kwLastClickEv:CamEvent = null;
	var kwLastClickMs:Float = 0;
	var kwTexts:Array<FlxText> = [];
	var kwTextUsed:Int = 0;
	var kwInputs:Map<String, PsychUIInputText> = new Map();
	var panelInputs:Map<String, PsychUIInputText> = new Map();
	var updatingNumInputs:Bool = false;
	/** Enter can make PsychUIInputText release focus during PlayState.update; consume that same key frame. */
	var suppressInputEnterShortcut:Bool = false;
	/** Preserve the global sound hotkeys and restore them when this editor closes. */
	var editorMuteKeysBackup:Dynamic = null;
	var editorMuteKeysOverridden:Bool = false;
	var ddOpen:Bool = false;
	var ddX:Float = 0;
	var ddY:Float = 0;
	var ddW:Float = 0;
	var ddOptions:Array<String> = [];
	var ddCurrent:Int = 0;
	var ddScroll:Int = 0;
	var ddPick:Int->Void = null;
	var ddRows:Array<FlxText> = [];
	var editBtnText:FlxText;
	var panelBtnTexts:Array<FlxText> = [];

	// ---------- playback / view ----------
	var songPos:Float = 0;
	var playing:Bool = false;
	/** true = เพิ่งเข้า editor ยังไม่เคยกด Play: ห้ามให้ PlayState เริ่มเพลงเอง */
	var holdInitialStart:Bool = true;
	var scriptSongStarted:Bool = false;
	var songStartedOnce:Bool = false;
	var songStartPending:Bool = false;
	var scriptSongEnded:Bool = false;
	/** Music completion callbacks run inside FlxSound.update; restart audio only after that update returns. */
	var previewEndPending:Bool = false;
	/** Video launched by a chart's Play Video event; owned by Camera Editor, not PlayState.startVideo(). */
	var previewEventVideo:VideoSprite = null;
	var previewEventVideoTime:Float = -1;
	var previewEventVideoCamera:String = 'hud';
	var resumeAfterSeek:Bool = false;
	var previewChar:Int = 0;
	var songLen:Float = 180000;
	var pps:Float = 42; // pixels per second
	var scrollMs:Float = 0;

	// ---------- drag ----------
	var mode:DragMode = None;
	var dragEv:CamEvent = null;
	var dragOld:CamEvent = null;
	var dragOffset:Float = 0;

	// ---------- UI ----------
	var canvas:FlxSprite;
	var tmpRect:Rectangle = new Rectangle();
	// alpha-blend scratch (fillRect REPLACES pixels, so translucent colors must go through BitmapData.draw)
	var blendSrc:BitmapData;
	var blendMatrix:Matrix = new Matrix();
	var blendCT:ColorTransform = new ColorTransform();
	var panelTitle:FlxText;
	var statusText:FlxText;
	var curStepText:FlxText;
	var timelineFollowText:FlxText;
	var cameraEventRows:Array<FlxText> = [];
	var cameraEventVisibleEntries:Array<CameraEventListEntry> = [];
	var cameraEventTitleCount:Int = -1;
	var selectedEventTitle:FlxText;
	var helpOpen:Bool = false;
	var helpTitle:FlxText;
	var helpText:FlxText;
	var helpFooter:FlxText;
	var helpDim:FlxSprite; // dims every editor sprite/text below it (canvas AND FlxText), unlike a rect on the canvas
	var helpPanel:FlxSprite;
	var helpPanelBuiltH:Int = -1;
	var helpLayered:Bool = false;
	var helpX:Float = 0;
	var helpY:Float = 0;
	var helpPanelW:Int = 700;
	var helpPanelH:Int = 360;
	var playButton:FlxText;
	var stopButton:FlxText;
	var rulerTexts:Array<FlxText> = [];
	// =====================================================================
	//  Theme (สีของ UI editor): ปรับเฉพาะสีโทนกลาง ๆ ของ UI สีสด (กรอบ VCam, เตือน) คงเดิม
	// =====================================================================
	static var THEME_NAMES:Array<String> = ['Midnight', 'Soft Slate', 'Mocha', 'Nord', 'Forest', 'Warm Night'];
	/** [เลื่อนสี (องศา), คูณความอิ่มตัว, คอนทราสต์, บวกความสว่าง] ของแต่ละธีม: คอนทราสต์ < 1 = ตัวอักษรไม่จ้า พื้นไม่ดำสนิท */
	static var THEME_PARAMS:Array<Array<Float>> = [
		[0, 1, 1, 0], // Midnight = สีเดิม
		[0, 0.72, 0.86, 0.035], // Soft Slate: เทาน้ำเงินนุ่ม ลดความจัด
		[50, 0.85, 0.88, 0.03], // Mocha: ม่วงอมน้ำตาลนุ่ม
		[-15, 0.9, 0.9, 0.04], // Nord: ฟ้าเทาเย็น
		[-85, 0.7, 0.88, 0.025], // Forest: เขียวหม่น
		[-170, 0.9, 0.86, 0.025] // Warm Night: โทนอำพัน ลดแสงฟ้า เหมาะกลางคืน
	];
	var themeIndex:Int = 0;
	var themeCache:Map<Int, Int> = new Map();
	var themeInverse:Map<Int, Int> = new Map();

	/** แปลงสีตามธีมปัจจุบัน (Midnight = คืนค่าเดิม) มี cache เพราะถูกเรียกทุกครั้งที่วาดสี่เหลี่ยม */
	function th(c:FlxColor):FlxColor
	{
		if (themeIndex == 0) return c;
		var key:Int = c;
		var cached = themeCache.get(key);
		if (cached != null)
		{
			var hit:Int = cached;
			return hit;
		}
		var out:Int = computeThemeColor(c, THEME_PARAMS[themeIndex]);
		themeCache.set(key, out);
		themeInverse.set(out, key);
		return out;
	}

	static function computeThemeColor(c:FlxColor, p:Array<Float>):FlxColor
	{
		if (c.alpha < 255) return c; // overlay โปร่งใสไม่แตะ
		var r = c.red / 255, g = c.green / 255, b = c.blue / 255;
		var mx = Math.max(r, Math.max(g, b));
		var mn = Math.min(r, Math.min(g, b));
		var l = (mx + mn) * 0.5;
		var d = mx - mn;
		var s = d == 0 ? 0.0 : d / (1 - Math.abs(2 * l - 1));
		if (s > 0.5) return c; // สีสด (กรอบ VCam, สีเตือน) คงเดิม
		var h:Float = 215; // สีเทากลาง ๆ ใช้เฉดฐานของ UI เดิมแล้วค่อยเลื่อนตามธีม
		if (d != 0)
		{
			if (mx == r) h = ((g - b) / d) % 6;
			else if (mx == g) h = (b - r) / d + 2;
			else h = (r - g) / d + 4;
			h *= 60;
			if (h < 0) h += 360;
		}
		if (s < 0.08) s = 0.08; // ให้เทาล้วนได้โทนของธีมเล็กน้อย
		var h2 = ((h + p[0]) % 360 + 360) % 360;
		var s2 = Math.min(1.0, s * p[1]);
		var l2 = Math.max(0.0, Math.min(1.0, 0.5 + (l - 0.5) * p[2] + p[3]));
		var cc = (1 - Math.abs(2 * l2 - 1)) * s2;
		var hp = h2 / 60;
		var x = cc * (1 - Math.abs(hp % 2 - 1));
		var r1 = 0.0, g1 = 0.0, b1 = 0.0;
		if (hp < 1) { r1 = cc; g1 = x; }
		else if (hp < 2) { r1 = x; g1 = cc; }
		else if (hp < 3) { g1 = cc; b1 = x; }
		else if (hp < 4) { g1 = x; b1 = cc; }
		else if (hp < 5) { r1 = x; b1 = cc; }
		else { r1 = cc; b1 = x; }
		var m = l2 - cc * 0.5;
		return FlxColor.fromRGB(Math.round((r1 + m) * 255), Math.round((g1 + m) * 255), Math.round((b1 + m) * 255), 255);
	}

	function loadSavedTheme():Void
	{
		try
		{
			var saved:Dynamic = FlxG.save.data.cameraEditorTheme;
			if (saved != null)
			{
				var i = Std.int(saved);
				if (i >= 0 && i < THEME_NAMES.length) themeIndex = i;
			}
		}
		catch (_:Dynamic) {}
	}

	function themeMenuItem(i:Int):CameraEditorMenuItem
		return {label: THEME_NAMES[i], action: function() setTheme(i)};

	function setTheme(index:Int):Void
	{
		if (index < 0 || index >= THEME_NAMES.length || index == themeIndex) return;
		// ข้อความ UI ที่สร้างไว้แล้ว: ย้อนกลับเป็นสีฐานก่อน แล้วใส่สีของธีมใหม่ (เฉพาะข้อความบนกล้อง UI ของ editor)
		var uiTexts:Array<FlxText> = [];
		var baseColors:Array<Int> = [];
		for (m in members)
		{
			if (m == null) continue;
			var t:FlxText = Std.downcast(m, FlxText);
			if (t == null || t.cameras == null || t.cameras.indexOf(editorUICamera) < 0) continue;
			var cur:Int = t.color;
			uiTexts.push(t);
			var base:Int = cur;
			if (themeInverse.exists(cur)) base = themeInverse.get(cur);
			baseColors.push(base);
		}
		themeIndex = index;
		themeCache = new Map();
		themeInverse = new Map();
		for (i in 0...uiTexts.length) uiTexts[i].color = th(baseColors[i]);
		helpPanelBuiltH = -1; // สร้างพื้นหลังหน้าต่าง Help ใหม่ด้วยสีของธีมใหม่
		try
		{
			FlxG.save.data.cameraEditorTheme = index;
			FlxG.save.flush();
		}
		catch (_:Dynamic) {}
		status('Theme: ' + THEME_NAMES[index]);
	}

	var buttons:Array<{txt:FlxText, fn:Void->Void}> = [];
	var jsonPicker:FileDialogHandler;
	var chartPicker:FileDialogHandler;
	var chartSavePicker:FileDialogHandler;
	var previewDragMouseX:Float = 0;
	var previewDragMouseY:Float = 0;
	var previewDragOriginX:Float = 0;
	var previewDragOriginY:Float = 0;
	var previewDragZoom:Float = 1;
	var menus:Array<CameraEditorMenu> = [];
	var activeMenu:String = null;
	var menuItemTexts:Array<FlxText> = [];
	var eventPickerOpen:Bool = false;
	var eventPickerIndex:Int = 0;
	var eventPickerScroll:Int = 0;
	var eventPickerTitle:FlxText;
	var eventPickerDescription:FlxText;
	var eventPickerFooter:FlxText;
	var eventPickerRows:Array<FlxText> = [];
	var manualHeldLane:Int = -1;
	var manualHeldCharacter:Int = -1;
	var previewScriptPaths:Array<String> = [];

	public function new(?songName:String = "test")
	{
		super();
		this.songName = songName;
		cameraEditorMode = true;
		onCameraEditorSongEnd = finishPreviewSong;
		onCameraEditorPlayVideo = function(videoName:String, cameraName:String, strumTime:Float):Void
		{
			showPreviewEventVideo(videoName, cameraName, strumTime);
		};
	}

	/** Select the mod that owns a chosen chart, and avoid retaining a stale mod when a base-game chart is opened. */
	static function selectChartMod(chartPath:String):Void
	{
		#if (sys && MODS_ALLOWED)
		if (chartPath == null || chartPath.length == 0) return;
		var normalized = chartPath.split('\\').join('/').toLowerCase();
		try normalized = FileSystem.fullPath(chartPath).split('\\').join('/').toLowerCase() catch (_:Dynamic) {}
		var previousMod = Mods.currentModDirectory;
		var knownMods = Mods.getGlobalMods();
		knownMods = knownMods == null ? [] : knownMods.copy();
		if (previousMod != null && previousMod.length > 0 && !knownMods.contains(previousMod))
			knownMods.push(previousMod);
		for (mod in knownMods)
		{
			var root = FileSystem.fullPath(Paths.mods(mod + '/')).split('\\').join('/').toLowerCase();
			if (!root.endsWith('/')) root += '/';
			if (normalized.startsWith(root))
			{
				Mods.currentModDirectory = mod;
				return;
			}
		}
		var modsRoot = FileSystem.fullPath(Paths.mods()).split('\\').join('/').toLowerCase();
		if (!modsRoot.endsWith('/')) modsRoot += '/';
		if (normalized.startsWith(modsRoot))
		{
			var relative = normalized.substr(modsRoot.length);
			var candidateMod = relative.split('/')[0];
			if (candidateMod != null && candidateMod.length > 0 && !['data', 'songs', 'stages', 'images', 'characters', 'scripts'].contains(candidateMod))
			{
				var candidateRoot = Paths.mods(candidateMod + '/');
				if (FileSystem.exists(candidateRoot) && FileSystem.isDirectory(candidateRoot))
				{
					Mods.currentModDirectory = candidateMod;
					return;
				}
			}
			// A path inside mods/ that did not resolve to a mod must not use a previously selected mod.
			Mods.currentModDirectory = '';
			return;
		}
		// Charts selected from the game's assets/preload folders belong to the base game.
		// Clear a stale mod override so Paths can resolve the original characters, stages and music.
		if (normalized.startsWith('assets/') || normalized.startsWith('preload/')
			|| normalized.indexOf('/assets/') >= 0 || normalized.indexOf('/preload/') >= 0)
			Mods.currentModDirectory = '';
		#end
	}

	/** Open a normal OS chart picker from the editors menu, then enter the camera editor. */
	public static function openChartPickerFromMenu():Void
	{
		returnToGameplay = false;
		returnToEditorMenu = true;
		menuChartPicker = new FileDialogHandler();
		menuChartPicker.open(null, 'Open Song Chart', [new FileFilter('Song Chart JSON', '*.json')], function()
		{
			var picker = menuChartPicker;
			try
			{
				var loaded:Dynamic = parseChartJson(picker.data);
				if (loaded == null) throw 'ไฟล์นี้ไม่ใช่ Song Chart JSON ที่รองรับ (ไม่พบ song / notes)';
				var chartSong:String = Std.string(Reflect.field(loaded, 'song'));
				if (chartSong.length == 0) throw 'ไม่พบชื่อเพลงใน Chart';
				Song.chartPath = picker.path;
				selectChartMod(picker.path);
				#if sys
				mergeSeparateDataEvents(loaded, picker.path);
				#end
				PlayState.SONG = cast loaded;
				PlayState.isStoryMode = false;
				Song.loadedSongName = Paths.formatToSongPath(chartSong);
				StageData.loadDirectory(PlayState.SONG);
				if (PlayState.SONG.stage == null || PlayState.SONG.stage.length == 0)
					PlayState.SONG.stage = StageData.vanillaSongStage(Song.loadedSongName);
				MusicBeatState.switchState(new CameraEditorState(Song.loadedSongName));
			}
			catch (e:Dynamic)
			{
				trace('Camera Editor chart picker: $e');
				try lime.app.Application.current.window.alert('เปิด Chart ไม่สำเร็จ:\n' + Std.string(e), 'Camera Editor') catch (_:Dynamic) {}
			}
			picker.destroy();
			menuChartPicker = null;
		}, null, function()
		{
			trace('Camera Editor chart picker: อ่านไฟล์ Chart ไม่สำเร็จ');
			if (menuChartPicker != null) menuChartPicker.destroy();
			menuChartPicker = null;
		});
	}

	function disableEditorMuteShortcut():Void
	{
		if (editorMuteKeysOverridden || FlxG.sound == null) return;
		try
		{
			var current:Dynamic = Reflect.field(FlxG.sound, 'muteKeys');
			if (current != null)
			{
				editorMuteKeysBackup = (cast current:Array<Dynamic>).copy();
				Reflect.setField(FlxG.sound, 'muteKeys', null); // typing 0 must not trigger Flixel's global mute hotkey
				editorMuteKeysOverridden = true;
			}
		}
		catch (e:Dynamic) trace('Camera Editor: could not disable muteKeys: ' + Std.string(e));
	}

	function restoreEditorMuteShortcut():Void
	{
		if (!editorMuteKeysOverridden || FlxG.sound == null) return;
		try Reflect.setField(FlxG.sound, 'muteKeys', editorMuteKeysBackup) catch (e:Dynamic) trace('Camera Editor: could not restore muteKeys: ' + Std.string(e));
		editorMuteKeysBackup = null;
		editorMuteKeysOverridden = false;
	}

	override function create()
	{
		disableEditorMuteShortcut();
		// Read data/<song>/events.json even when this editor was opened from the live game/editor
		// instead of through Open Chart. Select the chart's owning mod first so Paths.modFolders
		// cannot accidentally resolve another mod's event file.
		#if sys
		try
		{
			if (Song.chartPath != null && Song.chartPath.length > 0) selectChartMod(Song.chartPath);
			if (PlayState.SONG != null) mergeSeparateDataEvents(PlayState.SONG, Song.chartPath);
		}
		catch (e:Dynamic) trace('Camera Editor startup events load: ' + Std.string(e));
		#end
		// Preserve editor-menu music before PlayState's normal create path stops global music.
		if (returnToEditorMenu && !editorMenuMusicCaptured)
		{
			editorMenuMusic = FlxG.sound.music;
			if (editorMenuMusic != null)
			{
				editorMenuMusicWasPlaying = editorMenuMusic.playing;
				editorMenuMusicTime = editorMenuMusic.time;
				editorMenuMusicVolume = editorMenuMusic.volume;
				editorMenuMusic.pause();
			}
			editorMenuMusicCaptured = true;
		}
		// Detach the menu track so PlayState cannot overwrite it, but never leave FlxG.sound.music null:
		// Lua scripts created inside PlayState.create() read FlxG.sound.music.length (FunkinLua.new).
		// An empty placeholder is safe; PlayState replaces its contents when the song starts.
		if (returnToEditorMenu && editorMenuMusic != null && FlxG.sound.music == editorMenuMusic)
			FlxG.sound.music = new FlxSound();
		if (FlxG.sound.music == null) FlxG.sound.music = new FlxSound(); // สลับ chart จากในตัว editor: กัน FunkinLua/PlayState อ่าน music ที่เป็น null

		// Do not flush the global asset cache while entering Camera Editor. The live game may
		// still own cached base-game graphics/audio; PlayState.create() will load any missing
		// assets through Paths. Unconditionally clearing here can leave the editor without them.
		trace('Camera Editor: PlayState.create starting (keeping shared game asset cache)');
		try
		{
			super.create();
		}
		catch (e:Dynamic)
		{
			failEditorCreate('PlayState.create()', e);
			return;
		}
		trace('Camera Editor: PlayState.create finished, building editor UI');
		try
		{
			originalCameraVisibility = new ObjectMap<FlxCamera, Bool>();
			if (FlxG.cameras != null && FlxG.cameras.list != null)
				for (camera in FlxG.cameras.list)
					if (camera != null) originalCameraVisibility.set(camera, camera.visible);
			paused = true;
			// Preserve P-Slice's current normal cursor so custom hand states can be restored cleanly.
			if (FlxG.mouse.cursor != null) editorOriginalCursor = FlxG.mouse.cursor.bitmapData;
			FlxG.mouse.visible = true;
			// Keep PlayState's actual camera target, zoom, and stage. Only shrink its viewport
			// into the editor's preview rectangle; the game still owns and updates this camera.
			previewCamera = camGame;
			if (previewCamera != null)
			{
				originalGameCameraX = previewCamera.x;
				originalGameCameraY = previewCamera.y;
				originalGameCameraWidth = previewCamera.width;
				originalGameCameraHeight = previewCamera.height;
				// กล้องเกมคงขนาด/ตำแหน่งจริงไว้ (ไม่ย่อ ไม่ย้าย) แล้วใช้ UI canvas ปิดส่วนนอกวิวพอร์ตแทน
				computePreviewViewport();
				previewCamera.visible = true;
				previewCamera.alpha = 1;
				// A mod can attach full-screen post-process filters from onCreatePost.
				// They are not valid for the cropped editor viewport and can turn it black.
				previewCamera.filters = [];
				if (camFollow != null)
				{
					previewCamera.follow(camFollow, flixel.FlxCamera.FlxCameraFollowStyle.LOCKON, 0);
					previewCamera.snapToTarget();
				}
			}
			if (camHUD != null) camHUD.visible = false;
			// Remember pre-existing sounds so only transient script sounds are cleaned on exit.
			soundsBeforeEditor = [];
			for (sound in FlxG.sound.list.members)
				if (sound != null) soundsBeforeEditor.push(sound);
			stageHost = this;
			previewCharacters = [boyfriend, dad, gf];
			stageName = PlayState.curStage;
			defaultZoom = defaultCamZoom;
			stageCameraSpeed = cameraSpeed;
			if (boyfriend != null) charPos[0] = getCharCamPos(0);
			if (dad != null) charPos[1] = getCharCamPos(1);
			if (gf != null) charPos[2] = getCharCamPos(2);
			if (camFollow != null)
			{
				viewCenterX = camFollow.x;
				viewCenterY = camFollow.y;
				defaultCam = [camFollow.x, camFollow.y];
			}
			// Reuse PlayState's already allocated topmost transparent camera for editor
			// controls. This avoids allocating another full-screen camera and keeps the
			// editor UI above gameplay and mod camera overlays.
			editorUICamera = luaTpadCam;
			if (editorUICamera != null)
			{
				editorUICamera.visible = true;
				editorUICamera.alpha = 1;
				editorUICamera.filters = [];
				editorUICamera.bgColor = FlxColor.TRANSPARENT;
				editorUICamera.setPosition(0, 0);
				editorUICamera.setSize(FlxG.width, FlxG.height);
				editorUICamera.zoom = 1;
				editorUICamera.scroll.set(0, 0);
			}

			if (PlayState.SONG != null)
			{
				Conductor.songPosition = 0;
				songPos = 0;
				songLen = inst != null && inst.length > 0 ? inst.length + Conductor.offset : getChartLength();
			}

			// Canvas and every editor control stay on the main UI camera.
			canvas = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0x00000000, true);
			canvas.cameras = [editorUICamera];
			add(canvas);

			loadSavedTheme();
			menus = [
				{name: 'File', items: [
					{label: 'New Camera Events', action: newCameraEvents},
					{label: 'Open Song Chart...', action: openChart},
					{label: 'Open Event File...', action: openJson},
					{label: 'Save Camera Data (Events File)', action: saveCameraOnly},
					{label: 'Save All Events (Events File)', action: save},
					{label: 'Save Chart (All Events)', action: saveAllSongChart},
					{label: 'Save Chart (Camera Only)', action: function() saveFilteredSongChart(true)},
					{label: 'Save Chart (Non-Camera Events Only)', action: function() saveFilteredSongChart(false)},
					{label: 'Export Psych Engine 0.6.3 Lua...', action: exportPsych063Lua},
					{label: 'Export Psych Engine 1.0.4+ Lua...', action: exportPsych104Lua},
					{label: 'Export V-Slice Events JSON...', action: exportVSliceJson},
					{label: 'Export Codename HX...', action: exportCodenameHx},
					{label: 'Exit Editor', action: exitEditor}
				]},
				{name: 'Edit', items: [
					{label: 'Undo', action: undo},
					{label: 'Redo', action: redo},
					{label: 'Add Focus Event', action: addFocusEvent},
					{label: 'Add Zoom Event', action: addZoomEvent},
					{label: 'Add Tilt Event', action: addTiltEvent},
					{label: 'Insert Chart Event...', action: openChartEventPicker},
					{label: 'Delete Selected Event', action: function() { if (selected != null) removeEvent(selected); }}
				]},
				{name: 'View', items: [
					{label: 'Fit Preview', action: fitPreview},
					{label: 'Toggle Relative View', action: function() { setRelativeView(!relativeView); }},
					{label: 'Toggle Camera Preview', action: function() { showCameraFrame = !showCameraFrame; }},
					{label: 'Show Extended Bounds', action: function() { extendedBounds = !extendedBounds; }},
					{label: 'Toggle Passepartout', action: function() { passepartout = !passepartout; }},
					{label: 'Toggle Camera Zooms', action: toggleCameraZooms},
					{label: 'Toggle Extra Cameras', action: function() {
						hideOtherCameras = !hideOtherCameras;
						enforceEditorCameras();
						status(hideOtherCameras ? 'กล้องอื่นนอกจาก Game/HUD ถูกปิดใน Preview' : 'เปิดกล้องอื่นกลับตามสถานะเดิม');
					}},
					{label: 'Disable Song Lua', action: toggleSongLua},
					{label: 'Toggle Snap', action: function() { snapEnabled = !snapEnabled; status('Snap ' + (snapEnabled ? 'On' : 'Off')); }}
				]},
				{name: 'Theme', items: [for (i in 0...THEME_NAMES.length) themeMenuItem(i)]},
				{name: 'Playback', items: [
					{label: 'Play / Pause', action: togglePlay},
					{label: 'Stop and Rewind', action: stopPreview},
					{label: 'Play Test', action: playTest},
					{label: 'Go to Start', action: function() seekTo(0)}
				]},
				{name: 'Help', items: [
					{label: 'Keyboard and Mouse Controls', action: showHelp}
				]}
			];
			var bx = 8.0;
			for (menu in menus)
			{
				var menuName = menu.name;
				var t = new FlxText(bx + 8, 7, 0, menuName, 13);
				t.color = th(0xFFE3E8EF);
				t.cameras = [editorUICamera];
				add(t);
				buttons.push({txt: t, fn: function() activeMenu = activeMenu == menuName ? null : menuName});
				bx += t.width + 26;
			}
			playButton = new FlxText(bx + 4, 7, 68, 'Play', 13);
			playButton.color = th(0xFFE3E8EF);
			playButton.cameras = [editorUICamera];
			add(playButton);
			stopButton = new FlxText(bx + 86, 7, 58, 'Stop', 13);
			stopButton.color = th(0xFFE3E8EF);
			stopButton.cameras = [editorUICamera];
			add(stopButton);
			// จัดแถบเมนูทั้งแถวให้อยู่กลางจอ ตัวนับ FPS มุมซ้ายบนจะไม่บังปุ่ม (ตำแหน่งคลิก/กรอบอ่านจาก x ของข้อความ จึงตามไปเอง)
			var barLeft = buttons[0].txt.x - 8;
			var barRight = stopButton.x - 4 + 62;
			var barShift = Math.round((FlxG.width - (barRight - barLeft)) * 0.5 - barLeft);
			if (barShift > 0)
			{
				for (b in buttons) b.txt.x += barShift;
				playButton.x += barShift;
				stopButton.x += barShift;
			}
			// pool ของข้อความในเมนู: ต้องมีอย่างน้อยเท่าจำนวนรายการของเมนูที่ยาวที่สุด (เดิมตายตัว 8 เมนู File เลยล้มตอนมี 9 รายการ)
			var menuPoolSize = 8;
			for (m in menus)
				if (m.items.length > menuPoolSize) menuPoolSize = m.items.length;
			for (i in 0...menuPoolSize)
			{
				var itemText = new FlxText(0, 0, 396, '', 12);
				itemText.color = th(0xFFE3E8EF);
				itemText.cameras = [editorUICamera];
				itemText.visible = false;
				menuItemTexts.push(itemText);
				add(itemText);
			}

			panelTitle = new FlxText(PANEL_X + 14, PREV_Y + 9, PANEL_W - 28, "CHART EVENTS", 13);
			panelTitle.color = th(0xFFEDF1F6);
			panelTitle.cameras = [editorUICamera];
			add(panelTitle);
			for (i in 0...6)
			{
				var row = new FlxText(PANEL_X + 14, PREV_Y + 43 + i * 28, PANEL_W - 28, '', 11);
				row.color = th(0xFFE3E8EF);
				row.cameras = [editorUICamera];
				row.visible = false;
				cameraEventRows.push(row);
				cameraEventVisibleEntries.push(null);
				add(row);
			}
			selectedEventTitle = new FlxText(PANEL_X + 14, PREV_Y + 222, PANEL_W - 28, 'Select a chart event', 11);
			selectedEventTitle.color = th(0xFFEDF1F6);
			selectedEventTitle.wordWrap = false; // one line only, otherwise it wraps into the first property row
			selectedEventTitle.cameras = [editorUICamera];
			add(selectedEventTitle);
			refreshEventValueInputs();
			statusText = new FlxText(12, 687, 1250, "", 12);
			statusText.color = th(0xFF9ADFFF);
			statusText.cameras = [editorUICamera];
			add(statusText);
			curStepText = new FlxText(0, 687, 0, 'curStep: 0', 12);
			curStepText.color = th(0xFFFFD16C);
			curStepText.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF000000, 1);
			curStepText.cameras = [editorUICamera];
			add(curStepText);
			timelineFollowText = new FlxText(0, 687, 0, 'Follow: Realtime', 11);
			timelineFollowText.color = th(0xFFB8D7EF);
			timelineFollowText.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF000000, 1);
			timelineFollowText.cameras = [editorUICamera];
			add(timelineFollowText);
			eventPickerTitle = new FlxText(0, 0, 660, '', 16);
			eventPickerTitle.color = th(0xFFF0F4FA);
			eventPickerTitle.cameras = [editorUICamera];
			eventPickerTitle.visible = false;
			add(eventPickerTitle);
			for (i in 0...8)
			{
				var row = new FlxText(0, 0, 320, '', 12);
				row.color = th(0xFFE3E8EF);
				row.cameras = [editorUICamera];
				row.visible = false;
				eventPickerRows.push(row);
				add(row);
			}
			eventPickerDescription = new FlxText(0, 0, 280, '', 12);
			eventPickerDescription.color = th(0xFFBFC8D3);
			eventPickerDescription.cameras = [editorUICamera];
			eventPickerDescription.visible = false;
			add(eventPickerDescription);
			eventPickerFooter = new FlxText(0, 0, 660, '', 11);
			eventPickerFooter.color = th(0xFF9CA8B6);
			eventPickerFooter.cameras = [editorUICamera];
			eventPickerFooter.visible = false;
			add(eventPickerFooter);
			helpTitle = new FlxText(0, 0, 660, 'CAMERA EDITOR CONTROLS', 16);
			helpTitle.color = th(0xFFF0F4FA);
			helpTitle.cameras = [editorUICamera];
			helpTitle.visible = false;
			add(helpTitle);
			helpText = new FlxText(0, 0, 660, '', 13);
			helpText.color = th(0xFFE3E8EF);
			helpText.cameras = [editorUICamera];
			helpText.visible = false;
			add(helpText);
			helpFooter = new FlxText(0, 0, 660, '', 11);
			helpFooter.color = th(0xFF9CA8B6);
			helpFooter.cameras = [editorUICamera];
			helpFooter.visible = false;
			add(helpFooter);
			helpDim = new FlxSprite(0, 32).makeGraphic(FlxG.width, FlxG.height - 32, 0xFF000000);
			helpDim.alpha = 0.65;
			helpDim.cameras = [editorUICamera];
			helpDim.visible = false;
			add(helpDim);
			helpPanel = new FlxSprite();
			helpPanel.cameras = [editorUICamera];
			helpPanel.visible = false;
			add(helpPanel);

			// ข้อความสถานะ VCam (ตำแหน่ง/ซูมของกล้องจริงแบบ realtime + เตือนเมื่อ PlayState ไม่ตาม event)
			vcamInfoText = new FlxText(0, 0, 0, '', 11);
			vcamInfoText.color = th(0xFFECF7FF);
			vcamInfoText.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF000000, 1);
			vcamInfoText.cameras = [editorUICamera];
			vcamInfoText.visible = false;
			add(vcamInfoText);

			for (i in 0...(MAX_LAYERS_PER_TRACK * 3 + 1))
			{
				var lt = new FlxText(26, timelineTopY + RULER_H, TL_X - 26 - 44, '', 11);
				lt.color = th(0xFFE3E8EF);
				lt.cameras = [editorUICamera];
				lt.visible = false;
				layerLabels.push(lt);
				add(lt);
			}
			for (i in 0...6)
			{
				var bt = new FlxText(0, 0, 0, i % 2 == 0 ? '+' : '-', 12);
				bt.color = th(0xFFFFFFFF);
				bt.cameras = [editorUICamera];
				bt.visible = false;
				layerButtons.push(bt);
				add(bt);
			}

			for (i in 0...10)
			{
				var pl = new FlxText(0, 0, 0, '', 11);
				pl.color = th(0xFFC9D2DD);
				pl.cameras = [editorUICamera];
				pl.visible = false;
				propLabels.push(pl);
				add(pl);
				var pv = new FlxText(0, 0, 0, '', 11);
				pv.color = th(0xFFFFFFFF);
				pv.cameras = [editorUICamera];
				pv.visible = false;
				propValues.push(pv);
				add(pv);
				for (g in ['<', '>'])
				{
					var pa = new FlxText(0, 0, 0, g, 12);
					pa.color = th(0xFF9FB3C8);
					pa.cameras = [editorUICamera];
					pa.visible = false;
					propArrows.push(pa);
					add(pa);
				}
			}
			for (i in 0...80)
			{
				var sl = new FlxText(0, 0, 0, '', 10);
				sl.color = th(0xFFEAF2FA);
				sl.cameras = [editorUICamera];
				sl.visible = false;
				sectionLabels.push(sl);
				add(sl);
			}
			for (label in ['-', '+', 'Zoom'])
			{
				var zt = new FlxText(0, 0, 0, label, label == 'Zoom' ? 10 : 13);
				zt.color = th(0xFFE3E8EF);
				zt.cameras = [editorUICamera];
				zoomBtnTexts.push(zt);
				add(zt);
			}

			for (i in 0...72)
			{
				var t = new FlxText(0, timelineTopY + 4, 0, "", 10);
				t.color = th(0xFFCCCCCC);
				t.cameras = [editorUICamera];
				rulerTexts.push(t);
				add(t);
			}

			createKeyWindowUI();
			load();
			if (pendingImportedEvents != null)
			{
				try
				{
					events = cast pendingImportedEvents;
					pendingImportedEvents = null;
					normalizeDuplicateEditorKeys();
					sortEvents();
					selected = null; history = []; redoStack = [];
					status('นำเข้า Camera Events แล้ว (${events.length} events)');
				}
				catch (e:Dynamic)
				{
					status('นำเข้า Camera Events ไม่สำเร็จ: ' + Std.string(e));
					pendingImportedEvents = null;
				}
			}
			if (PlayState.SONG != null)
			{
				loadPreviewChart();
				syncCameraEvents();
				status('Live ${PlayState.SONG.song} | PlayState จริงกำลังอัปเดตฉาก แอนิเมชัน อีเวนต์ และกล้อง');
			}
			else
				status('ไม่มี Chart เพลง: ใช้ Open Chart เพื่อเลือกไฟล์ JSON ของเพลง');
		}
		catch (e:Dynamic)
		{
			failEditorCreate('editor UI setup', e);
			return;
		}
		trace('Camera Editor: ready');
	}

	/** Set when create() failed; update/draw are skipped so a half-built state cannot crash again. */
	var createFailed:Bool = false;

	/** Report a failed create() in a native message box (works even when nothing renders), then leave. */
	function failEditorCreate(stage:String, e:Dynamic):Void
	{
		createFailed = true;
		restoreEditorMuteShortcut();
		var message = 'Camera Editor failed at ' + stage + ':\n' + Std.string(e) + '\n' + haxe.CallStack.toString(haxe.CallStack.exceptionStack());
		trace(message);
		#if sys
		try File.saveContent('camera_editor_error.log', message) catch (_:Dynamic) {}
		#end
		try lime.app.Application.current.window.alert(message, 'Camera Editor') catch (_:Dynamic) {}
		FlxG.mouse.visible = true;
		if (returnToEditorMenu)
			MusicBeatState.switchState(new MasterEditorMenu());
		else
			MusicBeatState.switchState(new mikolka.vslice.ui.MainMenuState());
	}

	/** ขนาด scale ที่ใช้แสดงฉากใน preview: Relative = zoom ของ VCam x view zoom, Free = view zoom ล้วน ๆ */
	inline function previewScale():Float
		return Math.max(0.01, relativeView ? vcamPose.zoom * viewZoom : viewZoom);

	/** สลับ Relative / Free view โดยไม่ให้ภาพกระโดด (แปลง view zoom ให้ scale ที่เห็นเท่าเดิม) */
	function setRelativeView(value:Bool):Void
	{
		if (relativeView == value) return;
		var scaleNow = previewScale();
		relativeView = value;
		// Clear the Free View-only composited FX when switching modes; they are recaptured from the live camera if Free View is entered again.
		vcamFxFlashAlpha = 0;
		vcamFxFadeAlpha = 0;
		vcamFxShakeX = 0;
		vcamFxShakeY = 0;
		if (value)
			viewZoom = Math.max(0.05, Math.min(12, scaleNow / Math.max(0.01, vcamPose.zoom)));
		else
		{
			viewCenterX = vcamPose.x;
			viewCenterY = vcamPose.y;
			viewZoom = Math.max(0.05, Math.min(12, scaleNow));
		}
		status(value ? 'Relative View: VCam อยู่กับที่ ฉากเคลื่อนที่' : 'Free View: ลากเลื่อนจอได้อิสระ VCam เคลื่อนที่ในฉาก');
	}

	override function draw()
	{
		if (createFailed) return;
		// มุมมองของ editor (pan / zoom) ใช้เฉพาะตอนวาดเท่านั้น ไม่แตะสถานะกล้องของเกมจริง
		// PlayState จึงยังคุมกล้อง (follow, lerp, zoom bop) ตามปกติทั้งตอนหยุดและตอนเล่น
		if (previewCamera == null || stageHost == null)
		{
			super.draw();
			return;
		}
		// สำคัญ: ค่า zoom/scroll ของมุมมอง editor ต้องค้างอยู่บนกล้องจนกว่า render จะจบจริง (ลำดับ flush ขึ้นกับ renderer)
		// จึงไม่คืนค่าใน draw() แต่คืนที่ต้นเฟรมถัดไป (FlxG.signals.preUpdate) ก่อน tween / PlayState / Lua จะอ่านกล้อง
		restoreRealCameraView();
		// HaxeFlixel รุ่นใหม่ทำ Shake โดยเลื่อน flashSprite.x/y ระหว่าง update; เก็บ offset ก่อน
		// enforceEditorCameras() เรียก setPosition() แล้วล้าง offset นั้น เพื่อให้ Shake ไปอยู่ที่กรอบ VCam แทน
		if (!relativeView) capturePreviewCameraShakeForVCam();
		enforceEditorCameras();
		if (!editorViewHooked)
		{
			FlxG.signals.preUpdate.add(restoreRealCameraView);
			editorViewHooked = true;
		}
		realCamScrollX = previewCamera.scroll.x;
		realCamScrollY = previewCamera.scroll.y;
		realCamZoom = previewCamera.zoom;
		realCamAngle = previewCamera.angle;
		editorViewApplied = true;
		// Real-time VCam: FlxG.cameras.update (follow / lerp / zoom) ทำงานหลัง state.update จึงอ่านใน update() จะช้ากว่ากล้องจริง 1 เฟรม
		// อ่านค่ากล้องจริงตรงนี้ (ก่อนวาด) ทุกเฟรม ทั้งตอนเล่นและตอนหยุด ให้กรอบ VCam = กล้องจริงของเกมเสมอ
		// (ตอนหยุด updatePreviewCamera ส่ง pose ของ timeline เข้ากล้องจริงให้แล้ว จึงเห็นเท่ากัน)
		vcamPose.x = realCamScrollX + previewCamera.width * 0.5;
		vcamPose.y = realCamScrollY + previewCamera.height * 0.5;
		vcamPose.zoom = realCamZoom;
		vcamAngle = realCamAngle;
		if (relativeView)
		{
			viewCenterX = vcamPose.x;
			viewCenterY = vcamPose.y;
		}
		if (!relativeView)
		{
			// Free View: อย่าให้ camera FX กระทบทั้งฉากที่กำลัง free-pan.
			// เก็บ Flash/Fade/Shake ของกล้องจริงไว้ แล้ววาดซ้ำเฉพาะในกรอบ VCam ด้านบน canvas.
			previewCamera.angle = 0;
			captureAndMutePreviewCameraFX();
		}
		else
		{
			vcamFxFlashAlpha = 0;
			vcamFxFadeAlpha = 0;
			vcamFxShakeX = 0;
			vcamFxShakeY = 0;
		}
		previewCamera.zoom = previewScale();
		// กล้องเต็มจอ แต่ช่องมองอยู่ที่กึ่งกลางวิวพอร์ต (pvX..): ขยับจุดกึ่งกลางกล้องให้ viewCenter ไปตกที่กึ่งกลางช่องนั้นพอดี
		var drawScale = previewScale();
		var camCenterX = previewCamera.x + previewCamera.width * 0.5;
		var camCenterY = previewCamera.y + previewCamera.height * 0.5;
		var windowCenterX = pvX + pvW * 0.5;
		var windowCenterY = pvY + pvH * 0.5;
		// กล้องที่เอียง (Tilt) หมุนรอบ "กึ่งกลางกล้อง" ไม่ใช่กึ่งกลางช่องพรีวิว: หมุนจุดอ้างอิงกลับด้วยมุมตรงข้าม
		// เพื่อให้ viewCenter ยังตกที่กึ่งกลางช่องพรีวิวเหมือนตอนไม่เอียง (Free View ตั้งมุมเป็น 0 ไว้แล้ว จึงไม่กระทบ)
		var pivotX = windowCenterX;
		var pivotY = windowCenterY;
		if (Math.abs(previewCamera.angle) > 0.001)
		{
			var unrot = -previewCamera.angle * Math.PI / 180;
			var offX = windowCenterX - camCenterX;
			var offY = windowCenterY - camCenterY;
			pivotX = camCenterX + offX * Math.cos(unrot) - offY * Math.sin(unrot);
			pivotY = camCenterY + offX * Math.sin(unrot) + offY * Math.cos(unrot);
		}
		previewCamera.scroll.set(viewCenterX - (pivotX - camCenterX) / drawScale - previewCamera.width * 0.5,
			viewCenterY - (pivotY - camCenterY) / drawScale - previewCamera.height * 0.5);
		super.draw();
		// ตั้งใจไม่คืนค่าตรงนี้ (ดู restoreRealCameraView ที่ preUpdate)
		appliedCamScrollX = previewCamera.scroll.x;
		appliedCamScrollY = previewCamera.scroll.y;
		appliedCamZoom = previewCamera.zoom;
		appliedCamAngle = previewCamera.angle;
	}

	/** คำนวณวิวพอร์ตพรีวิวให้สัดส่วนเท่าจอเกมปัจจุบัน (FlxG.width : FlxG.height) แล้วจัดให้พอดีในกรอบ PREV_* */
	function computePreviewViewport():Void
	{
		var lens = cameraLensSize();
		var aspect = lens.width / Math.max(1, lens.height);
		var panelH = previewPanelHeight();
		var w:Int = PREV_W;
		var h:Int = Math.round(w / aspect);
		if (h > panelH)
		{
			h = panelH;
			w = Math.round(h * aspect);
		}
		pvW = Std.int(Math.max(16, Math.min(PREV_W, w)));
		pvH = Std.int(Math.max(16, Math.min(panelH, h)));
		pvX = PREV_X + Std.int((PREV_W - pvW) / 2);
		pvY = PREV_Y + Std.int((panelH - pvH) / 2);
	}

	/**
	 * ล็อกกล้องของ editor ให้อยู่ตำแหน่ง/ขนาดที่กรอบ VCam คำนวณไว้ทุกเฟรม
	 * สคริปต์ (Lua/HScript), อีเวนต์ (เช่น Cinematics) หรือ PlayState อาจย้าย/ย่อ/ซูมกล้องเกมหรือกล้อง UI
	 * ทำให้ฉากไม่ตรงกับกรอบ VCam และ UI เลื่อนหลุดจอ จึงคืนค่ากลับทุกเฟรม
	 */
	function enforceEditorCameras():Void
	{
		if (previewCamera != null && previewCamera.flashSprite != null)
		{
			// กล้องเกมต้องเป็นกล้องจริงเต็มขนาดเสมอ (ตำแหน่ง/ขนาดเดิมตอนเข้า editor) ภาพที่เห็นในพรีวิวคือส่วนที่เจาะช่องไว้บน UI canvas
			var camW = originalGameCameraWidth > 0 ? originalGameCameraWidth : FlxG.width;
			var camH = originalGameCameraHeight > 0 ? originalGameCameraHeight : FlxG.height;
			var moved = previewCamera.x != originalGameCameraX || previewCamera.y != originalGameCameraY || previewCamera.width != camW || previewCamera.height != camH;
			if (previewCamera.width != camW || previewCamera.height != camH) previewCamera.setSize(camW, camH);
			previewCamera.setPosition(originalGameCameraX, originalGameCameraY);
			previewCamera.visible = true;
			previewCamera.alpha = 1;
			if (moved && !viewportFixNotified)
			{
				viewportFixNotified = true;
				status('กล้องพรีวิวถูกสคริปต์/อีเวนต์ย้ายหรือย่อ ล็อกกลับให้แล้ว');
			}
		}
		if (editorUICamera != null && editorUICamera.flashSprite != null)
		{
			if (editorUICamera.x != 0 || editorUICamera.y != 0) editorUICamera.setPosition(0, 0);
			if (editorUICamera.width != FlxG.width || editorUICamera.height != FlxG.height) editorUICamera.setSize(FlxG.width, FlxG.height);
			if (editorUICamera.zoom != 1) editorUICamera.zoom = 1;
			if (editorUICamera.angle != 0) editorUICamera.angle = 0;
			if (editorUICamera.scroll.x != 0 || editorUICamera.scroll.y != 0) editorUICamera.scroll.set(0, 0);
			editorUICamera.visible = true;
			editorUICamera.alpha = 1;
			if (editorUICamera.filters != null && editorUICamera.filters.length > 0) editorUICamera.filters = [];
		}

		// Keep the editor preview deterministic: only the game viewport and the editor UI camera
		// may render. camHUD stays hidden as before; camOther and mod-created cameras are optional.
		if (FlxG.cameras != null && FlxG.cameras.list != null)
			for (camera in FlxG.cameras.list)
			{
				if (camera == null) continue;
				if (!originalCameraVisibility.exists(camera)) originalCameraVisibility.set(camera, camera.visible);
				if (camera == previewCamera || camera == editorUICamera)
					camera.visible = true;
				else if (camera == camHUD)
					camera.visible = false;
				else if (hideOtherCameras)
					camera.visible = false;
				else if (originalCameraVisibility.exists(camera))
					camera.visible = originalCameraVisibility.get(camera) == true;
			}
	}

	/** คืนค่า scroll / zoom จริงของกล้องเกมหลังวาดเฟรมเสร็จ เพื่อให้ PlayState คำนวณต่อจากค่าจริง */
	function restoreRealCameraView():Void
	{
		// Restore FX before the next PlayState/camera update, then capture them again just before render.
		restoreSuppressedPreviewCameraFX();
		if (!editorViewApplied) return;
		editorViewApplied = false;
		// ตอนสลับ state FlxG.cameras.reset() ทำลายกล้องก่อน destroy() (flashSprite = null) ห้ามแตะกล้องที่ถูกทำลายแล้ว (null object reference ใน setAngle)
		if (previewCamera == null || previewCamera.flashSprite == null) return;
		// ถ้าค่าบนกล้องยังเป็นค่าที่เราใส่ไว้ → คืนค่าจริง; ถ้ามีใครเขียนทับแล้ว (เช่น tween ของ Lua ใน plugin update) → ถือว่านั่นคือค่าจริงใหม่
		if (previewCamera.zoom == appliedCamZoom) previewCamera.zoom = realCamZoom;
		if (previewCamera.angle == appliedCamAngle) previewCamera.angle = realCamAngle;
		var sx = previewCamera.scroll.x == appliedCamScrollX ? realCamScrollX : previewCamera.scroll.x;
		var sy = previewCamera.scroll.y == appliedCamScrollY ? realCamScrollY : previewCamera.scroll.y;
		previewCamera.scroll.set(sx, sy);
	}

	/** Read a reflected numeric field safely across the HaxeFlixel versions bundled by mods. */
	function reflectedCameraFloat(field:String):Float
	{
		if (previewCamera == null) return 0;
		var value:Dynamic = Reflect.field(previewCamera, field);
		if (value == null) return 0;
		var number = Std.parseFloat(Std.string(value));
		return Math.isNaN(number) ? 0 : number;
	}

	/** Capture current screen shake displacement before setPosition() restores the camera container. */
	function capturePreviewCameraShakeForVCam():Void
	{
		vcamFxShakeX = 0;
		vcamFxShakeY = 0;
		if (previewCamera == null || previewCamera.flashSprite == null) return;

		var baseX = previewCamera.x * FlxG.scaleMode.scale.x
			+ previewCamera.width * 0.5 * FlxG.scaleMode.scale.x * previewCamera.initialZoom;
		var baseY = previewCamera.y * FlxG.scaleMode.scale.y
			+ previewCamera.height * 0.5 * FlxG.scaleMode.scale.y * previewCamera.initialZoom;
		var offset:Dynamic = Reflect.field(previewCamera, '_flashOffset');
		if (offset != null)
		{
			var ox:Dynamic = Reflect.field(offset, 'x');
			var oy:Dynamic = Reflect.field(offset, 'y');
			if (ox != null) baseX = previewCamera.x * FlxG.scaleMode.scale.x + Std.parseFloat(Std.string(ox));
			if (oy != null) baseY = previewCamera.y * FlxG.scaleMode.scale.y + Std.parseFloat(Std.string(oy));
		}

		// updateShake() applies world-space jitter multiplied by camera.zoom and the window scale.
		// Convert it back to world units because cameraFrameRect() scales world units by previewScale().
		var divisorX = previewCamera.zoom * FlxG.scaleMode.scale.x;
		var divisorY = previewCamera.zoom * FlxG.scaleMode.scale.y;
		if (Math.abs(divisorX) > 0.0001)
			vcamFxShakeX = (previewCamera.flashSprite.x - baseX) / divisorX;
		if (Math.abs(divisorY) > 0.0001)
			vcamFxShakeY = (previewCamera.flashSprite.y - baseY) / divisorY;
		if (Math.isNaN(vcamFxShakeX)) vcamFxShakeX = 0;
		if (Math.isNaN(vcamFxShakeY)) vcamFxShakeY = 0;
	}

	/** Find the active camera-shake offset without hard-depending on a particular HaxeFlixel version. */
	function previewCameraShakeOffset():Dynamic
	{
		if (previewCamera == null) return null;
		var value:Dynamic = Reflect.field(previewCamera, '_fxShakeOffset');
		if (value == null) value = Reflect.field(previewCamera, 'fxShakeOffset');
		if (value == null) value = Reflect.field(previewCamera, '_shakeOffset');
		return value;
	}

	/**
	 * Capture native camera FX and temporarily silence only their internal alpha/offset while the
	 * full Free View camera is drawn. Never hide flashSprite: it is the container for the whole scene.
	 */
	function captureAndMutePreviewCameraFX():Void
	{
		if (previewCamera == null) return;
		vcamFxFlashAlpha = 0;
		vcamFxFadeAlpha = 0;
		vcamFxHadFlashAlpha = false;
		vcamFxHadFadeAlpha = false;

		var flashAlpha:Dynamic = Reflect.field(previewCamera, '_fxFlashAlpha');
		if (flashAlpha != null)
		{
			vcamFxHadFlashAlpha = true;
			vcamFxRestoreFlashAlpha = reflectedCameraFloat('_fxFlashAlpha');
			var flashColor:Dynamic = Reflect.field(previewCamera, '_fxFlashColor');
			if (flashColor != null) vcamFxFlashColor = cast flashColor;
			vcamFxFlashAlpha = Math.max(0, Math.min(1, vcamFxRestoreFlashAlpha)) * vcamFxFlashColor.alpha / 255;
			Reflect.setField(previewCamera, '_fxFlashAlpha', 0.0);
		}

		var fadeAlpha:Dynamic = Reflect.field(previewCamera, '_fxFadeAlpha');
		if (fadeAlpha != null)
		{
			vcamFxHadFadeAlpha = true;
			vcamFxRestoreFadeAlpha = reflectedCameraFloat('_fxFadeAlpha');
			var fadeColor:Dynamic = Reflect.field(previewCamera, '_fxFadeColor');
			if (fadeColor != null) vcamFxFadeColor = cast fadeColor;
			vcamFxFadeAlpha = Math.max(0, Math.min(1, vcamFxRestoreFadeAlpha)) * vcamFxFadeColor.alpha / 255;
			Reflect.setField(previewCamera, '_fxFadeAlpha', 0.0);
		}

		// Shake should move the VCam frame only, not the editor viewport or its timeline/UI.
		var shake = previewCameraShakeOffset();
		if (shake != null)
		{
			var sx:Dynamic = Reflect.field(shake, 'x');
			var sy:Dynamic = Reflect.field(shake, 'y');
			vcamFxShakeX = sx == null ? 0 : Std.parseFloat(Std.string(sx));
			vcamFxShakeY = sy == null ? 0 : Std.parseFloat(Std.string(sy));
			if (Math.isNaN(vcamFxShakeX)) vcamFxShakeX = 0;
			if (Math.isNaN(vcamFxShakeY)) vcamFxShakeY = 0;
			vcamFxRestoreShakeX = vcamFxShakeX;
			vcamFxRestoreShakeY = vcamFxShakeY;
			Reflect.setField(shake, 'x', 0.0);
			Reflect.setField(shake, 'y', 0.0);
		}
		vcamFxMuted = true;
	}

	/** Restore the engine's native FX before PlayState/camera updates continue next frame. */
	function restoreSuppressedPreviewCameraFX():Void
	{
		if (!vcamFxMuted) return;
		if (previewCamera != null)
		{
			if (vcamFxHadFlashAlpha) Reflect.setField(previewCamera, '_fxFlashAlpha', vcamFxRestoreFlashAlpha);
			if (vcamFxHadFadeAlpha) Reflect.setField(previewCamera, '_fxFadeAlpha', vcamFxRestoreFadeAlpha);
			var shake = previewCameraShakeOffset();
			if (shake != null)
			{
				Reflect.setField(shake, 'x', vcamFxRestoreShakeX);
				Reflect.setField(shake, 'y', vcamFxRestoreShakeY);
			}
		}
		vcamFxMuted = false;
		vcamFxHadFlashAlpha = false;
		vcamFxHadFadeAlpha = false;
	}

	/** Blend Flash/Fade into the VCam rectangle (not the whole Free View viewport). */
	function combinedVCamFxColor():FlxColor
	{
		var fa = Math.max(0, Math.min(1, vcamFxFlashAlpha));
		var da = Math.max(0, Math.min(1, vcamFxFadeAlpha));
		var outA = da + fa * (1 - da); // fade is drawn over flash
		if (outA <= 0.001) return 0x00000000;
		var r = (vcamFxFadeColor.red * da + vcamFxFlashColor.red * fa * (1 - da)) / outA;
		var g = (vcamFxFadeColor.green * da + vcamFxFlashColor.green * fa * (1 - da)) / outA;
		var b = (vcamFxFadeColor.blue * da + vcamFxFlashColor.blue * fa * (1 - da)) / outA;
		return FlxColor.fromRGB(Std.int(Math.max(0, Math.min(255, Math.round(r)))),
			Std.int(Math.max(0, Math.min(255, Math.round(g)))), Std.int(Math.max(0, Math.min(255, Math.round(b)))),
			Std.int(Math.max(0, Math.min(255, Math.round(outA * 255)))));
	}

	/** Draw a screen-space FX tint only inside VCam. Handles a rotated VCam and clips to the preview viewport. */
	function drawVCamCameraFX(bounds:{x:Float, y:Float, width:Float, height:Float}, cameraAngle:Float):Void
	{
		if (canvas == null || canvas.pixels == null) return;
		var color = combinedVCamFxColor();
		if (color.alpha <= 0 || bounds.width <= 0 || bounds.height <= 0) return;
		var left = pvX;
		var top = pvY;
		var right = pvX + pvW;
		var bottom = pvY + pvH;
		if (Math.abs(cameraAngle) <= 0.05)
		{
			var x1 = Std.int(Math.max(left, Math.floor(bounds.x)));
			var y1 = Std.int(Math.max(top, Math.floor(bounds.y)));
			var x2 = Std.int(Math.min(right, Math.ceil(bounds.x + bounds.width)));
			var y2 = Std.int(Math.min(bottom, Math.ceil(bounds.y + bounds.height)));
			if (x2 > x1 && y2 > y1)
			{
				tmpRect.setTo(x1, y1, x2 - x1, y2 - y1);
				canvas.pixels.fillRect(tmpRect, color);
			}
			return;
		}

		var cx = bounds.x + bounds.width * 0.5;
		var cy = bounds.y + bounds.height * 0.5;
		var hw = bounds.width * 0.5;
		var hh = bounds.height * 0.5;
		var rad = -cameraAngle * Math.PI / 180;
		var cs = Math.cos(rad);
		var sn = Math.sin(rad);
		var xs:Array<Float> = [];
		var ys:Array<Float> = [];
		for (corner in [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]])
		{
			xs.push(cx + corner[0] * cs - corner[1] * sn);
			ys.push(cy + corner[0] * sn + corner[1] * cs);
		}
		var minY = Std.int(Math.max(top, Math.floor(Math.min(Math.min(ys[0], ys[1]), Math.min(ys[2], ys[3])))));
		var maxY = Std.int(Math.min(bottom, Math.ceil(Math.max(Math.max(ys[0], ys[1]), Math.max(ys[2], ys[3])))));
		for (py in minY...maxY)
		{
			var scanY = py + 0.5;
			var intersections:Array<Float> = [];
			for (i in 0...4)
			{
				var j = (i + 1) % 4;
				var yA = ys[i];
				var yB = ys[j];
				if ((yA <= scanY && yB > scanY) || (yB <= scanY && yA > scanY))
					intersections.push(xs[i] + (scanY - yA) * (xs[j] - xs[i]) / (yB - yA));
			}
			if (intersections.length < 2) continue;
			intersections.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
			var x1 = Std.int(Math.max(left, Math.floor(intersections[0])));
			var x2 = Std.int(Math.min(right, Math.ceil(intersections[intersections.length - 1])));
			if (x2 > x1)
			{
				tmpRect.setTo(x1, py, x2 - x1, 1);
				canvas.pixels.fillRect(tmpRect, color);
			}
		}
	}

	/** Load the selected chart's stage and characters into this standalone preview. */
	function setupPreviewScene():Void
	{
		stageLoadError = '';
		if (PlayState.SONG == null)
		{
			stageLoadError = "No chart loaded";
			return;
		}
		var sceneMemberStart = members.length;

		var song:Dynamic = PlayState.SONG;
		// PlayState normally prepares the active song/mod directory before asking for
		// StageData. The standalone Editor is a separate State, so repeat that setup here.
		try StageData.loadDirectory(PlayState.SONG) catch (e:Dynamic)
		{
			stageLoadError = 'StageData.loadDirectory: ' + Std.string(e);
			trace('Camera Editor StageData.loadDirectory: $e');
		}
		stageName = song.stage;
		if (stageName == null || stageName.length == 0)
		{
			stageName = StageData.vanillaSongStage(Paths.formatToSongPath(song.song));
			song.stage = stageName;
		}
		PlayState.curStage = stageName;

		var stageData:Dynamic = null;
		try stageData = StageData.getStageFile(stageName) catch (e:Dynamic) stageLoadError = 'StageData: $e';
		if (stageData == null && (stageLoadError == null || stageLoadError.length == 0))
			stageLoadError = 'StageData.getStageFile returned null';

		var bfPos:Array<Float> = readPair(stageData, "boyfriend", [770, 100]);
		var gfPos:Array<Float> = readPair(stageData, "girlfriend", [400, 130]);
		var dadPos:Array<Float> = readPair(stageData, "opponent", [100, 100]);
		stageCameraOffsets[0] = readPair(stageData, "camera_boyfriend", [0, 0]);
		stageCameraOffsets[1] = readPair(stageData, "camera_opponent", [0, 0]);
		stageCameraOffsets[2] = readPair(stageData, "camera_girlfriend", [0, 0]);
		var stageZoom:Dynamic = stageData == null ? null : Reflect.field(stageData, "defaultZoom");
		defaultZoom = stageZoom == null ? 1.0 : cast stageZoom;
		var cameraSpeedValue:Dynamic = stageData == null ? null : Reflect.field(stageData, "camera_speed");
		stageCameraSpeed = cameraSpeedValue != null && cameraSpeedValue > 0 ? cast cameraSpeedValue : 1.0;
		var hideGF:Bool = stageData != null && Reflect.field(stageData, "hide_girlfriend") == true;

		// PlayState's own stage loader expects character groups and camera fields to exist
		// before EventLoader.addstage(). Give it a detached PlayState host, not `cast this`.
		var gfGroup = new FlxSpriteGroup(gfPos[0], gfPos[1]);
		var dadGroup = new FlxSpriteGroup(dadPos[0], dadPos[1]);
		var bfGroup = new FlxSpriteGroup(bfPos[0], bfPos[1]);
		stageHost = new PlayState();
		stageHost.cameraEditorPreviewHost = true;
		stageHost.songName = Paths.formatToSongPath(song.song);
		// Give scripts a full-size logical gameplay camera. The cropped Preview camera
		// is only the editor's rendering surface, so exposing it as camGame scales camera
		// zoom values incorrectly and makes camera-related Lua events behave differently.
		stageHost.camGame = FlxG.camera;
		stageHost.camHUD = FlxG.camera;
		stageHost.camOther = FlxG.camera;
		stageHost.luaTpadCam = FlxG.camera;
		// Screen Shake events in preview affect the stage viewport, not editor controls.
		stageHost.chartEventPreviewCameras = [previewCamera, null];
		stageHost.defaultCamZoom = defaultZoom;
		stageHost.defaultStageZoom = defaultZoom;
		stageHost.cameraSpeed = stageCameraSpeed;
		var stageUIValue:Dynamic = stageData == null ? null : Reflect.field(stageData, "stageUI");
		PlayState.stageUI = stageUIValue != null && Std.string(stageUIValue).length > 0 ? Std.string(stageUIValue) : (stageData != null && Reflect.field(stageData, "isPixelStage") == true ? "pixel" : "normal");
		stageHost.BF_X = bfPos[0]; stageHost.BF_Y = bfPos[1];
		stageHost.DAD_X = dadPos[0]; stageHost.DAD_Y = dadPos[1];
		stageHost.GF_X = gfPos[0]; stageHost.GF_Y = gfPos[1];
		stageHost.boyfriendCameraOffset = stageCameraOffsets[0];
		stageHost.opponentCameraOffset = stageCameraOffsets[1];
		stageHost.girlfriendCameraOffset = stageCameraOffsets[2];
		stageHost.boyfriendGroup = bfGroup;
		stageHost.dadGroup = dadGroup;
		stageHost.gfGroup = gfGroup;
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// PlayState normally creates this group in create(). The detached preview host
		// skips that lifecycle, but script error reporting still expects the group.
		@:privateAccess stageHost.luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		var previewDebugGroup:FlxTypedGroup<psychlua.DebugLuaText> = @:privateAccess stageHost.luaDebugGroup;
		previewDebugGroup.cameras = [editorUICamera];
		add(previewDebugGroup);
		#end
		// Stage scripts often access camFollow even before the song's first section.
		stageHost.camFollow = new FlxObject(defaultCam[0], defaultCam[1], 1, 1);
		stageHost.add(stageHost.camFollow);
		// Use HaxeFlixel's actual camera-follow pipeline just as PlayState does. The
		// Timeline writes the follow target; FlxCamera handles world scroll/inertia.
		// The editor camera is an independent stage-workspace view. The gameplay camera
		// target remains on the detached host for scripts and the VCam overlay.
		previewCamera.target = null;
		PlayState.instance = stageHost;

		try
		{
			EventLoader.addstage(stageName);
		}
		catch (e:Dynamic)
		{
			stageLoadError = 'EventLoader: $e';
			trace('Camera Editor EventLoader ($stageName): $e');
		}

		var gfVersion:String = song.gfVersion;
		if (gfVersion == null || gfVersion.length == 0) gfVersion = 'gf';
		var gfChar:Character = null;
		if (!hideGF)
		{
			gfChar = new Character(0, 0, gfVersion);
			gfChar.scrollFactor.set(1, 1);
			startPreviewCharacter(gfChar);
			gfGroup.add(gfChar);
			previewCharacters[2] = gfChar;
			stageHost.gf = gfChar;
		}

		var dadChar = new Character(0, 0, song.player2);
		startPreviewCharacter(dadChar, true, gfPos);
		dadGroup.add(dadChar);
		previewCharacters[1] = dadChar;
		stageHost.dad = dadChar;

		var bfChar = new Character(0, 0, song.player1, true);
		startPreviewCharacter(bfChar);
		bfGroup.add(bfChar);
		previewCharacters[0] = bfChar;
		stageHost.boyfriend = bfChar;
		if (gfChar != null) stageHost.gfMap.set(gfChar.curCharacter, gfChar);
		stageHost.dadMap.set(dadChar.curCharacter, dadChar);
		stageHost.boyfriendMap.set(bfChar.curCharacter, bfChar);

		if (dadChar.curCharacter != null && camStartsWith(dadChar.curCharacter, 'gf'))
		{
			dadChar.setPosition(gfPos[0], gfPos[1]);
			if (previewCharacters[2] != null) previewCharacters[2].visible = false;
		}
		charPos = [getPreviewCharCamPos(0), getPreviewCharCamPos(1), getPreviewCharCamPos(2)];
		if (song.notes != null && song.notes.length > 0)
		{
			var firstSection:Dynamic = song.notes[0];
			if (firstSection.gfSection == true && previewCharacters[2] != null)
				defaultCam = getPreviewCharCamPos(2);
			else if (firstSection.mustHitSection == true)
				defaultCam = getPreviewCharCamPos(0);
			else
				defaultCam = getPreviewCharCamPos(1);
		}
		else
			defaultCam = getPreviewCharCamPos(1);
		viewCenterX = defaultCam[0];
		viewCenterY = defaultCam[1];
		stageHost.camFollow.setPosition(defaultCam[0], defaultCam[1]);
		FlxG.camera.follow(stageHost.camFollow, flixel.FlxCamera.FlxCameraFollowStyle.LOCKON, 0);
		FlxG.camera.followLerp = 0;
		FlxG.camera.zoom = defaultZoom;
		FlxG.camera.snapToTarget();
		loadPreviewChart();

		var objects:Dynamic = stageData == null ? null : Reflect.field(stageData, "objects");
		var stageObjects:Array<Dynamic> = objects == null ? [] : cast objects;
		if (stageObjects.length > 0)
		{
			try
			{
				var stageObjectMap:Map<String, FlxSprite> = StageData.addObjectsToState(stageObjects, hideGF ? null : gfGroup, dadGroup, bfGroup, stageHost);
				for (key => spr in stageObjectMap)
					if (!StageData.reservedNames.contains(key)) stageHost.variables.set(key, spr);
			}
			catch (e:Dynamic)
			{
				stageLoadError = (stageLoadError.length > 0 ? stageLoadError + '; ' : '') + 'Stage objects: ' + e;
				trace('Camera Editor StageData objects ($stageName): $e');
			}
		}

		// Load global and stage scripts before character scripts, matching the gameplay setup.
		loadPreviewLifecycleScripts();

		// Load stage scripts the same way gameplay does, so custom static stage sprites can spawn.
		loadPreviewScriptsFromFolder('stages/', stageName + '.lua', selectedChartModFolder('stages'));
		loadPreviewScriptsFromFolder('stages/', stageName + '.hx', selectedChartModFolder('stages'));
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		@:privateAccess stageHost.startCharacterScripts(gfChar == null ? '' : gfChar.curCharacter);
		@:privateAccess stageHost.startCharacterScripts(dadChar.curCharacter);
		@:privateAccess stageHost.startCharacterScripts(bfChar.curCharacter);
		#end
		loadPreviewChartScripts();

		if (!stageHost.members.contains(gfGroup) && !hideGF) stageHost.add(gfGroup);
		if (!stageHost.members.contains(dadGroup)) stageHost.add(dadGroup);
		if (!stageHost.members.contains(bfGroup)) stageHost.add(bfGroup);

		// EventLoader may register a BaseStage through PlayState.instance (host) or
		// MusicBeatState.getState() (the currently active Editor). Initialize both paths once.
		var stagesToCreate = stages.copy();
		if (stageHost.stages != null)
			for (stage in stageHost.stages)
				if (stage != null && !stagesToCreate.contains(stage)) stagesToCreate.push(stage);
		for (stage in stagesToCreate)
		{
			if (stage == null) continue;
			try stage.createPost() catch (e:Dynamic) trace('Camera Editor BaseStage createPost: $e');
			// BaseStage owns its own member tree in P-Slice and is not necessarily a child
			// of FlxState.members. Assign its sprites to the cropped Preview camera too.
			refreshStageTreeCamera(stage);
		}

		// Match PlayState's post-create lifecycle. Several stages/scripts only add final
		// props during onCreatePost, after characters and stage objects exist.
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		try stageHost.callOnScripts('onCreatePost') catch (e:Dynamic)
		{
			stageLoadError = (stageLoadError.length > 0 ? stageLoadError + '; ' : '') + 'Stage onCreatePost: ' + Std.string(e);
			trace('Camera Editor stage onCreatePost ($stageName): $e');
		}
		#end

		// P-Slice tracks BaseStage instances separately from FlxState.members. Preserve stages
		// registered to the active Editor and merge in any that EventLoader put on the host.
		if (stageHost.stages != null)
			for (stage in stageHost.stages)
				if (stage != null && !stages.contains(stage)) stages.push(stage);
		for (stage in stages)
			if (stage != null) refreshStageTreeCamera(stage);
		if (stageHost.stages != null)
			for (stage in stageHost.stages)
				if (stage != null) refreshStageTreeCamera(stage);

		// Refresh the cached targets after stage/character onCreate callbacks. Mods may
		// change cameraPosition or stage offsets there; PlayState's getter is the source of
		// truth for the focus values used by gameplay.
		for (who in 0...3)
			if (getPreviewCharacter(who) != null)
				charPos[who] = stageHost.getCharCamPos(who);
		if (song.notes != null && song.notes.length > 0)
		{
			var firstSection:Dynamic = song.notes[0];
			var firstWho = firstSection.gfSection && getPreviewCharacter(2) != null ? 2 : (firstSection.mustHitSection ? 0 : 1);
			defaultCam = charPos[firstWho];
		}
		else defaultCam = charPos[1];
		viewCenterX = defaultCam[0];
		viewCenterY = defaultCam[1];
		loadPreviewChart();

		// Move created stage/background members from the detached host into the editor's
		// active state. This ensures they're rendered through previewCamera and still update.
		var hostMembers = stageHost.members.copy();
		for (item in hostMembers)
		{
			if (item == null) continue;
			stageHost.remove(item, true);
			if (!members.contains(item)) add(item);
		}

		for (i in sceneMemberStart...members.length)
			setTreeCamera(members[i], previewCamera);
		// Initial stage and character objects are persistent scene content; bound only
		// objects scripts append during playback.
		lastKnownMemberCount = members.length;

		// Keep stage scripts' PlayState.instance.camFollow consistent with the first chart section.
		if (stageHost.camFollow != null) stageHost.camFollow.setPosition(defaultCam[0], defaultCam[1]);
		capturePreviewGroupMemberBaselines();
	}

	/** Load the same script families gameplay uses, while keeping them attached to the preview host. */
	function loadPreviewLifecycleScripts():Void
	{
		if (stageHost == null || PlayState.SONG == null) return;
		var songPath = 'data/${stageHost.songName}/';
		loadPreviewScriptsFromFolder('scripts/');
		loadPreviewScriptsFromFolder(songPath, null, selectedChartDirectory());
	}

	function selectedChartDirectory():String
	{
		#if sys
		if (Song.chartPath != null && Song.chartPath.length > 0)
			return haxe.io.Path.directory(Song.chartPath.split('\\').join('/'));
		#end
		return null;
	}

	function selectedChartModFolder(relativeFolder:String):String
	{
		#if sys
		if (Song.chartPath == null || Song.chartPath.length == 0) return null;
		var chartPath = Song.chartPath.split('\\').join('/');
		var lowerPath = chartPath.toLowerCase();
		var dataIndex = lowerPath.lastIndexOf('/data/');
		if (dataIndex >= 0)
			return haxe.io.Path.join([chartPath.substr(0, dataIndex), relativeFolder]) + '/';
		#end
		return null;
	}

	/** Load script files by their resolved path so charts from non-active mods still get their Lua. */
	function loadPreviewScriptsFromFolder(relativeFolder:String, ?onlyFile:String, ?extraFolder:String):Void
	{
		if (stageHost == null) return;
		#if (sys && (LUA_ALLOWED || HSCRIPT_ALLOWED))
		if (onlyFile != null)
		{
			var candidates:Array<String> = [];
			if (extraFolder != null && extraFolder.length > 0)
				candidates.push(haxe.io.Path.join([extraFolder, onlyFile]));
			var resolved:String = null;
			#if MODS_ALLOWED
			resolved = Paths.modFolders(relativeFolder + onlyFile);
			#else
			resolved = Paths.getSharedPath(relativeFolder + onlyFile);
			#end
			if (resolved != null && !candidates.contains(resolved)) candidates.push(resolved);
			for (path in candidates)
				if (NativeFileSystem.exists(path))
				{
					loadPreviewScriptAtPath(path);
					return;
				}
			// ไม่เจอในม็อดที่เปิดอยู่/ม็อดของ chart: ค้นทุกม็อดในโฟลเดอร์ mods/ (อีเวนต์จากหลายม็อดจะได้โหลดครบ)
			var foundElsewhere = findFileInAllMods(relativeFolder, onlyFile);
			if (foundElsewhere != null) loadPreviewScriptAtPath(foundElsewhere);
			return;
		}
		var folders = Mods.directoriesWithFile(Paths.getSharedPath(), relativeFolder);
		if (extraFolder != null && extraFolder.length > 0 && FileSystem.exists(extraFolder) && !folders.contains(extraFolder))
			folders.push(extraFolder);
		var chartDirectory = selectedChartDirectory();
		if (chartDirectory != null && relativeFolder.indexOf('data/') == 0 && FileSystem.exists(chartDirectory) && !folders.contains(chartDirectory))
			folders.push(chartDirectory);
		for (folder in folders)
		{
			try
			{
				for (file in NativeFileSystem.readDirectory(folder))
				{
					var path = haxe.io.Path.join([folder, file]);
					loadPreviewScriptAtPath(path);
				}
			}
			catch (e:Dynamic)
				trace('Camera Editor scripts $folder: $e');
		}
		#end
	}

	/** โฟลเดอร์ root ของทุกม็อดที่ติดตั้งอยู่ (mods/<ชื่อ>/) ไม่สนว่าเปิดใช้งานอยู่หรือไม่ */
	function allModRoots():Array<String>
	{
		var roots:Array<String> = [];
		#if (sys && MODS_ALLOWED)
		try
		{
			var modsDir = Paths.mods();
			if (NativeFileSystem.exists(modsDir) && NativeFileSystem.isDirectory(modsDir))
				for (name in NativeFileSystem.readDirectory(modsDir))
				{
					var root = Paths.mods(name + '/');
					if (NativeFileSystem.isDirectory(root) && !roots.contains(root)) roots.push(root);
				}
		}
		catch (e:Dynamic)
			trace('Camera Editor list mods: $e');
		#end
		return roots;
	}

	/** หาไฟล์ <relativeFolder><file> ในทุกม็อด (ชื่อตรงก่อน แล้วค่อยลองไม่สนตัวพิมพ์เล็ก/ใหญ่และ _ แทนช่องว่าง) */
	function findFileInAllMods(relativeFolder:String, file:String):String
	{
		#if sys
		var wanted = file.toLowerCase().split(' ').join('_');
		for (root in allModRoots())
		{
			var exact = root + relativeFolder + file;
			if (NativeFileSystem.exists(exact)) return exact;
			var folder = root + relativeFolder;
			try
			{
				if (!NativeFileSystem.exists(folder) || !NativeFileSystem.isDirectory(folder)) continue;
				for (candidate in NativeFileSystem.readDirectory(folder))
					if (candidate.toLowerCase().split(' ').join('_') == wanted) return haxe.io.Path.join([folder, candidate]);
			}
			catch (_:Dynamic) {}
		}
		#end
		return null;
	}

	function loadPreviewScriptAtPath(path:String):Void
	{
		if (stageHost == null || path == null || !NativeFileSystem.exists(path)) return;
		var lowerPath = path.toLowerCase();
		if (!camEndsWith(lowerPath, '.lua') && !camEndsWith(lowerPath, '.hx')) return;
		var scriptIdentity = path.split('\\').join('/').toLowerCase();
		#if sys
		try scriptIdentity = FileSystem.fullPath(path).split('\\').join('/').toLowerCase() catch (_:Dynamic) {}
		#end
		if (previewScriptPaths.contains(scriptIdentity)) return;
		previewScriptPaths.push(scriptIdentity);
		#if LUA_ALLOWED
		if (camEndsWith(lowerPath, '.lua'))
		{
			var normalized = path.split('\\').join('/').toLowerCase();
			var alreadyLoaded = false;
			for (script in stageHost.luaArray)
				if (script.scriptName.split('\\').join('/').toLowerCase() == normalized)
					alreadyLoaded = true;
			if (!alreadyLoaded) new FunkinLua(path);
		}
		#end
		#if HSCRIPT_ALLOWED
		if (camEndsWith(lowerPath, '.hx') && !Iris.instances.exists(path))
			stageHost.initHScript(path);
		#end
	}

	function loadPreviewChartScripts():Void
	{
		if (stageHost == null) return;
		var eventsSeen:Array<String> = [];
		for (event in previewChartEvents)
			if (!eventsSeen.contains(event.name)) eventsSeen.push(event.name);
		var typesSeen:Array<String> = [];
		for (note in previewNotes)
			if (note.noteType != null && note.noteType.length > 0 && !typesSeen.contains(note.noteType)) typesSeen.push(note.noteType);
		#if LUA_ALLOWED
		for (event in eventsSeen)
			loadPreviewScriptsFromFolder('custom_events/', event + '.lua', selectedChartModFolder('custom_events'));
		for (noteType in typesSeen)
			loadPreviewScriptsFromFolder('custom_notetypes/', noteType + '.lua', selectedChartModFolder('custom_notetypes'));
		#end
		#if HSCRIPT_ALLOWED
		for (event in eventsSeen)
			loadPreviewScriptsFromFolder('custom_events/', event + '.hx', selectedChartModFolder('custom_events'));
		for (noteType in typesSeen)
			loadPreviewScriptsFromFolder('custom_notetypes/', noteType + '.hx', selectedChartModFolder('custom_notetypes'));
		#end
		for (event in previewChartEvents)
		{
			try @:privateAccess stageHost.eventPushed({strumTime: event.strumTime, event: event.name, value1: event.value1, value2: event.value2}) catch (e:Dynamic)
				trace('Camera Editor eventPushed: $e');
			try stageHost.callOnScripts('onEventPushed', [event.name, event.value1, event.value2, event.strumTime]) catch (e:Dynamic)
				trace('Camera Editor onEventPushed: $e');
		}
		// Match PlayState: early triggers are calculated after eventPushed/onEventPushed.
		for (event in previewChartEvents)
			recalculatePreviewChartEventTime(event);
		previewChartEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		rebuildChartCameraEvents();
	}

	function recalculatePreviewChartEventTime(event:PreviewChartEvent):Void
	{
		if (event == null) return;
		var earlyTrigger:Float = 0;
		if (stageHost != null)
			try earlyTrigger = @:privateAccess stageHost.eventEarlyTrigger({strumTime: event.strumTime, event: event.name, value1: event.value1, value2: event.value2}) catch (e:Dynamic)
				trace('Camera Editor eventEarlyTrigger: $e');
		event.time = event.strumTime - earlyTrigger;
	}

	function addAvailableChartEvent(name:String, description:String):Void
	{
		if (name == null || name.trim().length == 0) return;
		var key = name.toLowerCase();
		for (event in availableChartEvents)
			if (event.name.toLowerCase() == key)
			{
				if ((event.description == null || event.description.length == 0) && description != null)
					event.description = description;
				return;
			}
		availableChartEvents.push({name: name, description: description == null ? '' : description});
	}

	function addChartEventFilesFromFolder(folder:String):Void
	{
		#if sys
		if (folder == null || folder.length == 0 || !FileSystem.exists(folder) || !FileSystem.isDirectory(folder)) return;
		for (file in NativeFileSystem.readDirectory(folder))
		{
			if (file == null || camStartsWith(file.toLowerCase(), 'readme.')) continue;
			var path = haxe.io.Path.join([folder, file]);
			if (NativeFileSystem.isDirectory(path)) continue;
			var lower = file.toLowerCase();
			var extension = camEndsWith(lower, '.txt') ? '.txt' : (camEndsWith(lower, '.lua') ? '.lua' : (camEndsWith(lower, '.hx') ? '.hx' : ''));
			if (extension.length == 0) continue;
			var name = file.substr(0, file.length - extension.length);
			var description = '';
			if (extension == '.txt')
				try description = NativeFileSystem.getContent(path) catch (_:Dynamic) {}
			addAvailableChartEvent(name, description);
		}
		#end
	}

	function loadAvailableChartEvents():Void
	{
		availableChartEvents = [];
		for (definition in ChartingState.defaultEvents)
			if (definition != null && definition.length > 0)
				addAvailableChartEvent(definition[0], definition.length > 1 ? definition[1] : '');
		#if sys
		#if MODS_ALLOWED
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'custom_events/'))
			addChartEventFilesFromFolder(folder);
		#end
		addChartEventFilesFromFolder(selectedChartModFolder('custom_events'));
		// อีเวนต์จากม็อดอื่น ๆ ที่ติดตั้งไว้ (แม้ไม่ได้เปิดใช้งาน) ก็แสดงให้เลือกวางได้
		for (root in allModRoots())
			addChartEventFilesFromFolder(root + 'custom_events/');
		#end
		// Keep chart events visible even when their mod has no .txt description file.
		for (event in previewChartEvents)
			addAvailableChartEvent(event.name, 'Already used in this chart.');
		availableChartEvents.sort((a, b) -> a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0));
		cameraEventListDirty = true;
	}

	function openChartEventPicker():Void
	{
		if (PlayState.SONG == null)
		{
			status('โหลด Song Chart ก่อน เพื่อวาง Chart Event');
			return;
		}
		loadAvailableChartEvents();
		if (availableChartEvents.length == 0)
		{
			status('ไม่พบ Chart Event ที่วางได้ในเกมหรือ Mod ที่เลือก');
			return;
		}
		eventPickerOpen = true;
		eventPickerIndex = Std.int(Math.max(0, Math.min(eventPickerIndex, availableChartEvents.length - 1)));
		eventPickerScroll = Std.int(Math.max(0, Math.min(eventPickerIndex, availableChartEvents.length - eventPickerRows.length)));
		activeMenu = null;
	}

	function closeChartEventPicker():Void
	{
		eventPickerOpen = false;
		if (eventPickerTitle != null) eventPickerTitle.visible = false;
		if (eventPickerDescription != null) eventPickerDescription.visible = false;
		if (eventPickerFooter != null) eventPickerFooter.visible = false;
		for (row in eventPickerRows) row.visible = false;
	}

	function moveChartEventPickerSelection(delta:Int):Void
	{
		if (availableChartEvents.length == 0) return;
		eventPickerIndex = Std.int(Math.max(0, Math.min(availableChartEvents.length - 1, eventPickerIndex + delta)));
		if (eventPickerIndex < eventPickerScroll) eventPickerScroll = eventPickerIndex;
		if (eventPickerIndex >= eventPickerScroll + eventPickerRows.length)
			eventPickerScroll = eventPickerIndex - eventPickerRows.length + 1;
	}

	function placeSelectedChartEvent():Void
	{
		if (PlayState.SONG == null || eventPickerIndex < 0 || eventPickerIndex >= availableChartEvents.length) return;
		var definition = availableChartEvents[eventPickerIndex];
		var eventTime:Float = Math.max(0, Math.min(songLen, songPos));
		var chartEventTime:Float = Math.max(0, eventTime - ClientPrefs.data.noteOffset);
		var value1 = '';
		var value2 = '';
		switch (definition.name.toLowerCase())
		{
			case 'set camzoom': value1 = Std.string(defaultZoom);
			case 'zoomcamera' | 'zoom camera': value1 = Std.string(defaultZoom);
		}
		if (PlayState.SONG.events == null) PlayState.SONG.events = [];
		var grouped:Array<Dynamic> = null;
		for (raw in PlayState.SONG.events)
		{
			if (raw == null || !Std.isOfType(raw, Array)) continue;
			var row:Array<Dynamic> = cast raw;
			if (row.length < 2 || row[0] == null) continue;
			var rawTime = Std.parseFloat(Std.string(row[0]));
			if (!Math.isNaN(rawTime) && Math.abs(rawTime - chartEventTime) < 0.01)
			{
				grouped = row;
				break;
			}
		}
		if (grouped == null)
		{
			grouped = [chartEventTime, []];
			PlayState.SONG.events.push(grouped);
		}
		var subEvents:Array<Dynamic> = grouped[1] == null ? [] : cast grouped[1];
		var placedRawSubEvent:Array<Dynamic> = [definition.name, value1, value2];
		subEvents.push(placedRawSubEvent);
		grouped[1] = subEvents;
		PlayState.SONG.events.sort((a, b) ->
		{
			var ta = a != null && a.length > 0 && a[0] != null ? Std.parseFloat(Std.string(a[0])) : 0;
			var tb = b != null && b.length > 0 && b[0] != null ? Std.parseFloat(Std.string(b[0])) : 0;
			ta < tb ? -1 : (ta > tb ? 1 : 0);
		});

		#if LUA_ALLOWED
		loadPreviewScriptsFromFolder('custom_events/', definition.name + '.lua', selectedChartModFolder('custom_events'));
		#end
		#if HSCRIPT_ALLOWED
		loadPreviewScriptsFromFolder('custom_events/', definition.name + '.hx', selectedChartModFolder('custom_events'));
		#end
		var addedEvent:PreviewChartEvent = {time: eventTime, strumTime: eventTime, name: definition.name, value1: value1, value2: value2, rawRow: null, rawSubEvent: null};
		loadPreviewChart();
		syncCameraEditorChartEvents(true);
		selected = null;
		selectedChartComponent = null;
		for (source in previewChartEvents)
			if (source.rawSubEvent == placedRawSubEvent)
			{
				addedEvent.time = source.time;
				addedEvent.strumTime = source.strumTime;
				addedEvent.rawRow = source.rawRow;
				addedEvent.rawSubEvent = source.rawSubEvent;
				selectedChartSource = source;
				for (link in chartCameraLinks)
					if (link.source == source)
					{
						selected = link.camera;
						selectedChartComponent = link.component;
						break;
					}
				break;
			}
		cameraEventListDirty = true;
		refreshEventValueInputs();
		// Recalculate the new event for the editor timeline. The live PlayState API
		// has already rebuilt pending eventNotes without re-pushing existing events.
		recalculatePreviewChartEventTime(addedEvent);
		if (selectedChartSource != null) selectedChartSource.time = addedEvent.time;
		previewChartEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		rebuildChartCameraEvents();
		selected = null;
		for (link in chartCameraLinks)
			if (link.source == selectedChartSource)
			{
				selected = link.camera;
				selectedChartComponent = link.component;
				break;
			}

		previewNoteCursor = -1;
		scriptNoteCursor = 0;
		while (scriptNoteCursor < previewNotes.length && previewNotes[scriptNoteCursor].time <= songPos)
		{
			previewNoteCursor = scriptNoteCursor;
			scriptNoteCursor++;
		}
		previewChartEventCursor = 0;
		while (previewChartEventCursor < previewChartEvents.length && previewChartEvents[previewChartEventCursor].time < eventTime)
			previewChartEventCursor++;
		lastPreviewTime = Math.max(-1, songPos - 0.01);
		lastBeatTick = -1;
		closeChartEventPicker();
		status('วาง ${definition.name} ที่ ${fmtTime(eventTime)} แล้ว (บันทึกลง Chart ในหน่วยความจำ)');
	}

	function getChartLength():Float
	{
		if (PlayState.SONG == null) return 180000;
		var endTime:Float = 0;
		firstChartNoteTime = Math.POSITIVE_INFINITY;
		if (PlayState.SONG.notes != null)
		{
			var bpm:Float = PlayState.SONG.bpm > 0 ? PlayState.SONG.bpm : 100;
			for (section in PlayState.SONG.notes)
			{
				if (section.changeBPM && section.bpm > 0) bpm = section.bpm;
				var beats:Float = section.sectionBeats > 0 ? section.sectionBeats : 4;
				endTime += beats * 60000 / bpm;
				if (section.sectionNotes != null)
					for (raw in section.sectionNotes)
						if (raw != null && raw.length >= 2)
						{
							var noteTime:Float = raw[0];
							var sustain:Float = raw.length > 2 && raw[2] != null ? Math.max(0, raw[2]) : 0;
							if (!Math.isNaN(noteTime))
							{
								firstChartNoteTime = Math.min(firstChartNoteTime, noteTime);
								endTime = Math.max(endTime, noteTime + sustain);
							}
						}
			}
		}
		for (event in previewChartEvents)
			endTime = Math.max(endTime, event.time);
		return Math.max(1, endTime);
	}

	function readPair(data:Dynamic, field:String, fallback:Array<Float>):Array<Float>
	{
		if (data != null)
		{
			var value:Dynamic = Reflect.field(data, field);
			if (value != null)
			{
				var pair:Array<Dynamic> = cast value;
				if (pair != null && pair.length >= 2)
					return [cast pair[0], cast pair[1]];
			}
		}
		return [fallback[0], fallback[1]];
	}

	function startPreviewCharacter(char:Character, gfCheck:Bool = false, ?gfPos:Array<Float>):Void
	{
		if (gfCheck && char.curCharacter != null && camStartsWith(char.curCharacter, 'gf') && gfPos != null)
		{
			char.setPosition(gfPos[0], gfPos[1]);
			char.scrollFactor.set(1, 1);
			char.danceEveryNumBeats = 2;
		}
		if (char.positionArray != null && char.positionArray.length >= 2)
		{
			char.x += char.positionArray[0];
			char.y += char.positionArray[1];
		}
	}

	function setTreeCamera(item:FlxBasic, cam:FlxCamera):Void
	{
		if (item == null) return;
		// Stage trees are revisited when dynamic groups change size. Only assign a new
		// camera array when it actually changes; allocating `[cam]` for every child on
		// every refresh was an unbounded per-frame garbage source in particle-heavy stages.
		var assigned:Dynamic = Reflect.field(item, 'cameras');
		var cameraArray:Array<Dynamic> = Std.isOfType(assigned, Array) ? cast assigned : null;
		var matches = cameraArray != null && cameraArray.length == 1 && cameraArray[0] == cam;
		// P-Slice's Flixel fork uses `.camera` in a number of its own states, while
		// standard Flixel code uses `.cameras`. Set both for compatibility.
		if (Std.isOfType(item, FlxSprite))
		{
			var spr:FlxSprite = cast item;
			if (!matches) spr.cameras = [cam];
			if (Reflect.field(spr, 'camera') != cam)
				try Reflect.setProperty(spr, 'camera', cam) catch (_:Dynamic) {}
		}
		else
		{
			if (!matches)
				try Reflect.setProperty(item, 'cameras', [cam]) catch (_:Dynamic) {}
			if (Reflect.field(item, 'camera') != cam)
				try Reflect.setProperty(item, 'camera', cam) catch (_:Dynamic) {}
		}
		// BaseStage / FlxSpriteGroup members aren't always direct FlxState children,
		// so walk each nested member tree after both create() and createPost().
		var children:Dynamic = Reflect.field(item, "members");
		if (children != null && Std.isOfType(children, Array))
		{
			for (child in (cast children:Array<Dynamic>))
				if (child != null && Std.isOfType(child, FlxBasic)) setTreeCamera(cast child, cam);
		}
	}

	function refreshStageTreeCamera(stage:Dynamic):Void
	{
		if (stage == null) return;
		var size = -1;
		var children:Dynamic = Reflect.field(stage, 'members');
		if (children != null && Std.isOfType(children, Array))
		{
			var list:Array<Dynamic> = cast children;
			size = list.length;
			// Check nested group sizes without walking every sprite in large stage particle groups.
			for (child in list)
			{
				if (child == null) continue;
				var nested:Dynamic = Reflect.field(child, 'members');
				if (nested != null && Std.isOfType(nested, Array)) size += (cast nested:Array<Dynamic>).length;
			}
		}
		for (cached in stageTreeCameraSizes)
			if (cached.stage == stage)
			{
				if (cached.size == size) return;
				cached.size = size;
				setTreeCamera(cast stage, previewCamera);
				return;
			}
		stageTreeCameraSizes.push({stage: stage, size: size});
		setTreeCamera(cast stage, previewCamera);
	}

	function getPreviewCharCamPos(index:Int):Array<Float>
	{
		var char = index >= 0 && index < previewCharacters.length ? previewCharacters[index] : null;
		if (char == null) return [defaultCam[0], defaultCam[1]];
		var mid = char.getMidpoint();
		var result:Array<Float>;
		switch (index)
		{
			case 0: result = [mid.x - 100 - (char.cameraPosition[0] - stageCameraOffsets[0][0]), mid.y - 100 + char.cameraPosition[1] + stageCameraOffsets[0][1]];
			case 1: result = [mid.x + 150 + char.cameraPosition[0] + stageCameraOffsets[1][0], mid.y - 100 + char.cameraPosition[1] + stageCameraOffsets[1][1]];
			case 2: result = [mid.x + char.cameraPosition[0] + stageCameraOffsets[2][0], mid.y + char.cameraPosition[1] + stageCameraOffsets[2][1]];
			default: result = [mid.x, mid.y];
		}
		mid.put();
		return result;
	}

	static final PREVIEW_SING:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	/**
	 * สร้างรายการโน้ตสำหรับซิงก์ท่าตัวละคร โดยใช้กฎเดียวกับ PlayState.generateNotes
	 * (ฝั่ง BF/Opponent, gfSection / GF Sing, Alt Animation, No Animation, ตัด ghost note ซ้ำ)
	 */
	function addPreviewNoteFromChart(section:Dynamic, raw:Array<Dynamic>):Void
	{
		var time:Float = raw[0];
		if (Math.isNaN(time) || raw[1] == null) return;
		var rawData:Int = Std.int(raw[1]);
		var lane:Int = rawData % 4;
		// Chart lane 0-3 belongs to mustHitSection; lanes 4-7 invert ownership.
		// Do not infer ownership from rawData < 4 alone or player/opponent note callbacks get swapped.
		var mustHitSection:Bool = Reflect.field(section, 'mustHitSection') == true;
		var playerSide:Bool = rawData > 3 ? !mustHitSection : mustHitSection;
		var sustain:Float = raw.length > 2 && raw[2] != null ? raw[2] : 0;
		if (Math.isNaN(sustain)) sustain = 0;
		var noteType:String = raw.length > 3 && raw[3] != null && Std.isOfType(raw[3], String) ? raw[3] : '';
		var normalizedNoteType = noteType == null ? '' : noteType.trim().toLowerCase();
		// Hurt notes are only un-hittable when they belong to the player; opponent notes still play normally.
		if (playerSide && normalizedNoteType == 'hurt note') return;
		for (i in 0...previewNotes.length)
		{
			var other = previewNotes[previewNotes.length - 1 - i];
			if (other.time < time - 1) break;
			if (other.time == time && other.lane == lane && other.playerSide == playerSide && other.noteType == noteType) return;
		}
		var gfNote:Bool = (section.gfSection == true && playerSide == (section.mustHitSection == true)) || noteType == 'GF Sing';
		var alt:Bool = (section.altAnim == true && !playerSide) || noteType == 'Alt Animation';
		var anim:String = noteType == 'No Animation' ? '' : PREVIEW_SING[lane] + (alt ? '-alt' : '');
		previewNotes.push({
			time: time, who: gfNote ? 2 : (playerSide ? 0 : 1), lane: lane, playerSide: playerSide,
			animation: anim, sustain: sustain, noteType: noteType
		});
	}

	function loadPreviewChart():Void
	{
		// Keep the retired simulation buffer empty and reuse it; gameplay already owns
		// the real note objects, so the editor never needs a second per-note copy.
		previewNotes.resize(0);
		blockedPreviewNoteKeys = new Map();
		animSyncDirty = true;
		firstChartNoteTime = Math.POSITIVE_INFINITY;
		chartCameraEvents = [];
		chartCameraLinks = [];
		selectedChartSource = null;
		sectionCameraTargets = [];
		cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
		previewChartEvents = [];
		if (PlayState.SONG == null)
		{
			cameraEventListDirty = true;
			rebuildCameraEventList();
			return;
		}
		buildSectionCameraCache();
		if (PlayState.SONG.notes != null)
		for (section in PlayState.SONG.notes)
		{
			if (section.sectionNotes == null) continue;
			for (raw in section.sectionNotes)
			{
				if (raw == null || raw.length < 2) continue;
				var t:Float = raw[0];
				if (!Math.isNaN(t)) firstChartNoteTime = Math.min(firstChartNoteTime, t);
				addPreviewNoteFromChart(section, raw);
			}
		}
		previewNotes.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		previewNoteCursor = -1;
		if (PlayState.SONG.events != null)
			for (rawEvent in PlayState.SONG.events)
			{
				if (rawEvent == null || rawEvent.length < 2 || rawEvent[1] == null) continue;
				var eventTime:Float = rawEvent[0] + ClientPrefs.data.noteOffset;
				var rawSubEvents:Array<Dynamic> = cast rawEvent[1];
				if (rawSubEvents == null) continue;
				for (rawSubEvent in rawSubEvents)
				{
					if (rawSubEvent == null || rawSubEvent.length < 1) continue;
					var name = Std.string(rawSubEvent[0]);
					var value1 = rawSubEvent.length > 1 && rawSubEvent[1] != null ? Std.string(rawSubEvent[1]) : '';
					var value2 = rawSubEvent.length > 2 && rawSubEvent[2] != null ? Std.string(rawSubEvent[2]) : '';
					var event:PreviewChartEvent = {
						time: eventTime, strumTime: eventTime, name: name, value1: value1, value2: value2,
						rawRow: cast rawEvent, rawSubEvent: cast rawSubEvent
					};
					previewChartEvents.push(event);
				}
			}
		previewChartEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		rebuildChartCameraEvents();
	}

	function rebuildChartCameraEvents():Void
	{
		chartCameraEvents = [];
		chartCameraLinks = [];
		for (event in previewChartEvents) parseChartCameraEvent(event);

		// Chart camera events used to be shown as reference-only blocks. Promote one visible
		// canonical key per component/time into the editor's editable key collection while
		// keeping each link to its original SONG.events sub-event for round-trip saving.
		// Capture candidates before promoting: after the first key is inserted the alias shadow
		// check would intentionally hide sibling representations of the same event.
		var promotableLinks:Array<ChartCameraLink> = [];
		for (link in chartCameraLinks)
			if (chartCameraLinkVisible(link)) promotableLinks.push(link);
		var promotedAny = false;
		for (link in promotableLinks)
		{
			var hasEditorKey = false;
			var component = cameraTrackComponent(link.camera.track);
			for (key in events)
				if (key != null && cameraTrackComponent(key.track) == component && sameCameraEventTime(key.time, link.camera.time))
				{
					hasEditorKey = true;
					break;
				}
			if (!hasEditorKey)
			{
				events.push(link.camera);
				promotedAny = true;
			}
		}
		if (promotedAny)
		{
			events.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
			recountLayers();
			syncCameraEvents();
		}
		chartCameraEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		rebuildPreviewBopEvents();
		cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
		cameraEventListDirty = true;
		rebuildCameraEventList();
		refreshEventValueInputs();
	}

	function rebuildPreviewBopEvents():Void
	{
		previewBopEvents.resize(0);
		previewZoomDecayEvents.resize(0);
		for (event in previewChartEvents)
		{
			if (event.name == null) continue;
			var name = event.name.toLowerCase();
			if (name == 'set camera bopping')
			{
				var frequency = Std.parseFloat(event.value1);
				var multiplier = Std.parseFloat(event.value2);
				if (Math.isNaN(frequency) || frequency <= 0) frequency = 4;
				if (Math.isNaN(multiplier)) multiplier = 1;
				previewBopEvents.push({time: event.time, frequency: frequency, multiplier: multiplier});
			}
			else if (name == 'zoom camera')
			{
				// V-Slice temporarily raises camera decay to 7 while its zoom tween runs.
				// Reconstruct that same window on seeks and during playback.
				var values = event.value1 == null ? [] : event.value1.split(',');
				if (values.length != 2) continue;
				var steps = values.length > 0 ? Std.parseFloat(values[0]) : 0;
				var scale = Std.parseFloat(values[1]);
				var stepMs = Conductor.getCrotchetAtTime(event.time) / 4;
				var duration = steps * stepMs;
				if (!Math.isNaN(steps) && steps >= 0 && !Math.isNaN(scale) && scale > 0 && !Math.isNaN(duration) && duration > 0)
					previewZoomDecayEvents.push({time: event.time, endTime: event.time + duration});
			}
		}
		previewBopEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		previewZoomDecayEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
	}

	function previewZoomDecayAt(time:Float):Float
	{
		var low = 0;
		var high = previewZoomDecayEvents.length;
		while (low < high)
		{
			var mid = (low + high) >>> 1;
			if (previewZoomDecayEvents[mid].time <= time) low = mid + 1;
			else high = mid;
		}
		if (low <= 0) return 1;
		return time < previewZoomDecayEvents[low - 1].endTime ? 7 : 1;
	}

	function cameraBopSettingsAt(time:Float):{frequency:Float, multiplier:Float}
	{
		var low = 0;
		var high = previewBopEvents.length;
		while (low < high)
		{
			var mid = (low + high) >>> 1;
			if (previewBopEvents[mid].time <= time) low = mid + 1;
			else high = mid;
		}
		previewBopScratch.frequency = low > 0 ? previewBopEvents[low - 1].frequency : 4;
		previewBopScratch.multiplier = low > 0 ? previewBopEvents[low - 1].multiplier : 1;
		return previewBopScratch;
	}

	function syncPreviewBoppingState(time:Float):Void
	{
		if (stageHost == null) return;
		var bop = cameraBopSettingsAt(time);
		stageHost.camZoomingFrequency = bop.frequency;
		stageHost.camZoomingMult = bop.multiplier;
		stageHost.camZooming = songName != 'tutorial' && firstChartNoteTime != Math.POSITIVE_INFINITY && time >= firstChartNoteTime;
	}

	function rebuildCameraEventList():Void
	{
		if (!cameraEventListDirty) return;
		cameraEventList = [];
		for (link in chartCameraLinks)
			if (chartCameraLinkVisible(link))
				cameraEventList.push({
					time: link.source.time,
					name: link.source.name + (link.component == null ? '' : ' - ' + link.component),
					camera: link.camera,
					source: link.source,
					component: link.component
				});
		for (source in previewChartEvents)
		{
			var hasAnyCameraLink = false;
			for (link in chartCameraLinks)
				if (link.source == source)
				{
					hasAnyCameraLink = true;
				}
			// Camera events that are represented by an editor key (or an equivalent alias) must
			// not remain as a second read-only row in the event list.
			if (!hasAnyCameraLink)
				cameraEventList.push({time: source.time, name: source.name, camera: null, source: source, component: null});
		}
		for (camera in events)
		{
			var linked = chartCameraLinkFor(camera);
			var defaultName = camera.track == 'focus' ? 'Focus - custom' : (camera.track == 'tilt' ? 'Tilt - custom' : (camera.track == 'kick' ? 'Add Camera Zoom' : 'Zoom - custom'));
			cameraEventList.push({
				time: camera.time,
				name: linked != null && linked.source != null ? linked.source.name + (linked.component == null ? '' : ' - ' + linked.component) : defaultName,
				camera: camera,
				source: linked == null ? null : linked.source,
				component: linked == null ? null : linked.component
			});
		}
		cameraEventList.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : (a.name < b.name ? -1 : (a.name > b.name ? 1 : 0))));
		var maxScroll = Std.int(Math.max(0, cameraEventList.length - cameraEventRows.length));
		cameraEventListScroll = Std.int(Math.max(0, Math.min(maxScroll, cameraEventListScroll)));
		cameraEventListDirty = false;
	}

	function selectCameraListEntry(entry:CameraEventListEntry):Void
	{
		if (entry == null) return;
		selected = entry.camera;
		var linked = entry.camera == null ? null : chartCameraLinkFor(entry.camera);
		selectedChartSource = entry.source != null ? entry.source : (linked == null ? null : linked.source);
		selectedChartComponent = entry.component != null ? entry.component : (linked == null ? null : linked.component);
		refreshEventValueInputs();
		seekTo(entry.time);
		if (entry.camera != null && selectedChartSource == null) status('เลือก ${entry.name} ที่ ${fmtTime(entry.time)}');
		else if (selectedChartSource != null) status('เลือก ${entry.name} ที่ ${fmtTime(entry.time)}');
	}

	/** Updates the selected-event heading only. Raw Value 1/Value 2 widgets were removed because
	 *  their fixed-position PsychUIInputText child controls overlapped native camera properties.
	 *  Chart values remain preserved internally when importing/exporting events. */
	function refreshEventValueInputs():Void
	{
		var source = selectedChartSource;
		if (source != null)
		{
			if (isCameraChartEventName(source.name))
				setTextIfChanged(selectedEventTitle, source.name + '  •  ' + fmtTime(source.time));
			else
				setTextIfChanged(selectedEventTitle, source.name + '  •  ' + fmtTime(source.time));
			return;
		}
		var keyTitle = selected == null ? 'Select a chart event'
			: (selected.track == 'focus' ? 'Focus Camera key'
			: (selected.track == 'zoom' ? 'Zoom Camera key'
			: (selected.track == 'tilt' ? 'Tilt Camera key'
			: (selected.track == 'kick' ? 'Add Camera Zoom key' : 'General Camera key'))));
		setTextIfChanged(selectedEventTitle, keyTitle);
	}

	function addChartCameraEvent(source:PreviewChartEvent, camera:CamEvent, component:String):Void
	{
		chartCameraEvents.push(camera);
		chartCameraLinks.push({camera: camera, source: source, component: component});
	}

	function sourceForChartCamera(camera:CamEvent):PreviewChartEvent
	{
		selectedChartComponent = null;
		var link = chartCameraLinkFor(camera);
		if (link == null) return null;
		selectedChartComponent = link.component;
		return link.source;
	}

	function chartCameraLinkFor(camera:CamEvent):ChartCameraLink
	{
		if (camera == null) return null;
		for (link in chartCameraLinks)
			if (link.camera == camera) return link;
		// A preview-chart rebuild reconstructs CamEvent wrappers. Match the promoted editor key
		// back to its raw chart row by track component/time so it remains editable afterwards.
		var wanted = cameraTrackComponent(camera.track);
		var fallback:ChartCameraLink = null;
		for (link in chartCameraLinks)
			if (link.camera != null && cameraTrackComponent(link.camera.track) == wanted && sameCameraEventTime(link.camera.time, camera.time))
			{
				if (fallback == null || (link.source != null && fallback.source != null && editorCameraEventPriority(link.source.name) > editorCameraEventPriority(fallback.source.name)))
					fallback = link;
			}
		return fallback;
	}

	function parseChartCameraEvent(event:PreviewChartEvent):Void
	{
		var name = event.name == null ? '' : event.name.toLowerCase();
		var parts = event.value2 == null ? [] : event.value2.split(',');
		var duration = parts.length > 0 ? Std.parseFloat(parts[0]) * 1000 : 0;
		if (Math.isNaN(duration)) duration = 0;
		var ease = parts.length > 1 && parts[1].trim().length > 0 ? parts[1].trim() : 'linear';
		if (name == 'target camera')
		{
			var target: Int = -1;
			switch (event.value1 == null ? '' : event.value1.toLowerCase().trim())
			{
				case 'bf' | 'boyfriend' | '0': target = 0;
				case 'dad' | 'opponent' | '1': target = 1;
				case 'gf' | 'girlfriend' | '2': target = 2;
			}
			var values = event.value2 == null ? [] : event.value2.split(',');
			var x = values.length > 0 ? Std.parseFloat(values[0]) : 0;
			var y = values.length > 1 ? Std.parseFloat(values[1]) : 0;
			var steps = values.length > 2 ? Std.parseFloat(values[2]) : 0;
			var targetEase = values.length > 3 && values[3].trim().length > 0 ? values[3].trim() : 'linear';
			var targetAutoRelease = hasAutoReleaseMarker(event.value2);
			if (Math.isNaN(x)) x = 0;
			if (Math.isNaN(y)) y = 0;
			if (Math.isNaN(steps) || steps < 0) steps = 0;
			var stepMs = Conductor.getCrotchetAtTime(event.time) / 4;
			var targetDuration = targetEase.toLowerCase() == 'instant' || targetEase.toLowerCase() == 'classic' ? 0 : steps * stepMs;
			addChartCameraEvent(event, {time: event.time, track: 'focus', x: x, y: y, zoom: defaultZoom, duration: targetDuration, ease: targetEase, target: target, autoRelease: targetAutoRelease}, 'focus');
		}
		else if (name == 'zoom camera')
		{
			var values = event.value1 == null ? [] : event.value1.split(',');
			if (values.length != 2) return;
			var steps = values.length > 0 ? Std.parseFloat(values[0]) : 0;
			var scale = values.length > 1 ? Std.parseFloat(values[1]) : 1;
			if (Math.isNaN(steps) || steps < 0) steps = 0;
			if (Math.isNaN(scale) || scale <= 0) scale = 1;
			var stepMs = Conductor.getCrotchetAtTime(event.time) / 4;
			var zoomEase = event.value2 == null || event.value2.trim().length == 0 ? 'linear' : event.value2.trim();
			addChartCameraEvent(event, {time: event.time, track: 'zoom', x: 0, y: 0, zoom: defaultZoom * scale, duration: steps * stepMs, ease: zoomEase, target: -1}, 'zoom');
		}
		else if (name == 'focuscamera' || name == 'focus camera')
		{
			// ตรงกับ custom_events/FocusCamera.lua: Value 1 = Character,X,Y (X,Y = offset ข้ามได้)
			// Value 2 = Duration(เป็น Step),Ease  ว่าง/0 = ทันที  Value 1 ว่าง = ปล่อยกล้องกลับไปตามปกติ
			var stepMs = Math.max(1, Conductor.getCrotchetAtTime(event.time) / 4);
			var e:CamEvent = {time: event.time, track: 'focus', x: 0, y: 0, zoom: defaultZoom, duration: 0, ease: 'linear', target: -1, autoRelease: hasAutoReleaseMarker(event.value2)};
			var raw = event.value1 == null ? '' : event.value1.trim();
			if (raw.length == 0)
			{
				e.target = -2; // ปล่อยกล้อง
			}
			else
			{
				var data = raw.split(',');
				switch (data[0].trim().toLowerCase())
				{
					case '0' | 'bf' | 'boyfriend': e.target = 0;
					case '1' | 'dad' | 'opponent': e.target = 1;
					case '2' | 'gf' | 'girlfriend': e.target = 2;
				}
				var ox = data.length > 1 ? Std.parseFloat(data[1]) : 0;
				var oy = data.length > 2 ? Std.parseFloat(data[2]) : 0;
				e.x = Math.isNaN(ox) ? 0 : ox;
				e.y = Math.isNaN(oy) ? 0 : oy;
				var rawTween = event.value2 == null ? '' : event.value2.trim();
				if (rawTween.length > 0)
				{
					var tween = rawTween.split(',');
					var steps = Std.parseFloat(tween[0]);
					if (tween[0].trim() != '0' && !Math.isNaN(steps) && steps > 0)
					{
						e.duration = steps * stepMs;
						e.ease = 'smootherStepOut'; // ค่าเริ่มต้นของสคริปต์เมื่อไม่ระบุ Ease
						if (tween.length > 1)
						{
							var easeName = tween[1].trim();
							if (easeName == 'CLASSIC')
							{
								e.ease = 'expoOut';
								e.duration += 1000;
							}
							else if (easeName == 'INSTANT')
							{
								e.ease = 'linear';
								e.duration = 0;
							}
							else e.ease = easeName.length > 0 ? easeName : 'linear';
						}
					}
				}
			}
			addChartCameraEvent(event, e, 'focus');
		}
		else if (name == 'zoomcamera' || name == 'zoom camera')
		{
			var zoom = Std.parseFloat(event.value1);
			if (Math.isNaN(zoom)) zoom = defaultZoom;
			addChartCameraEvent(event, {time: event.time, track: 'zoom', x: 0, y: 0, zoom: zoom, duration: duration, ease: ease, target: -1}, 'zoom');
		}
		else if (name == 'camera follow pos' || name == 'camera warp pos')
		{
			// Camera Warp Pos เป็นอีเวนต์ native ของ custom engine สำหรับ snap กล้องทันที
			// ส่วน Camera Follow Pos ยังคงเป็นอีเวนต์เดิมสำหรับพฤติกรรม follow ปกติ
			if ((event.value1 == null || event.value1.trim().length == 0) && (event.value2 == null || event.value2.trim().length == 0))
				addChartCameraEvent(event, {time: event.time, track: 'focus', x: 0, y: 0, zoom: defaultZoom, duration: 0, ease: 'linear', target: -2}, 'focus');
			else
			{
				var x = event.value1 == null || event.value1.trim().length == 0 ? 0 : Std.parseFloat(event.value1);
				var y = event.value2 == null || event.value2.trim().length == 0 ? 0 : Std.parseFloat(event.value2);
				if (Math.isNaN(x)) x = 0;
				if (Math.isNaN(y)) y = 0;
				addChartCameraEvent(event, {time: event.time, track: 'focus', x: x, y: y, zoom: defaultZoom, duration: 0, ease: 'linear', target: -1}, 'focus');
			}
		}
		else if (name == 'camera focus xy')
		{
			// Native absolute XY focus: Value 1 = X,Y; Value 2 = Steps,Ease like FocusCamera.lua.
			var xy = event.value1 == null ? [] : event.value1.split(',');
			if (xy.length < 2) return;
			var x = Std.parseFloat(xy[0]);
			var y = Std.parseFloat(xy[1]);
			if (Math.isNaN(x) || Math.isNaN(y)) return;
			var timing = event.value2 == null ? [] : event.value2.split(',');
			var steps = timing.length > 0 ? Std.parseFloat(timing[0]) : 0;
			if (Math.isNaN(steps) || steps < 0) steps = 0;
			var stepMs = Math.max(1, Conductor.getCrotchetAtTime(event.time) / 4);
			var xyDuration = steps * stepMs;
			var xyEase = timing.length > 1 && timing[1].trim().length > 0 ? timing[1].trim() : 'smootherStepOut';
			if (xyEase.toUpperCase() == 'CLASSIC') { xyEase = 'expoOut'; if (xyDuration > 0) xyDuration += 1000; }
			else if (xyEase.toUpperCase() == 'INSTANT') { xyEase = 'linear'; xyDuration = 0; }
			addChartCameraEvent(event, {time: event.time, track: 'focus', x: x, y: y, zoom: defaultZoom, duration: xyDuration, ease: xyEase, target: -1, autoRelease: hasAutoReleaseMarker(event.value2)}, 'focus');
		}
		else if (name == 'rol cam' || name == 'roll camera')
		{
			// event Rol cam ในตัว PlayState: Value 1 = มุม (องศา), Value 2 = วินาที,Ease (ว่าง = 1 วินาที, quadInOut)
			var angle = Std.parseFloat(event.value1);
			if (Math.isNaN(angle)) angle = 0;
			var tiltParts = event.value2 == null ? [] : event.value2.split(',');
			var seconds = tiltParts.length > 0 ? Std.parseFloat(tiltParts[0]) : Math.NaN;
			if (Math.isNaN(seconds)) seconds = 1;
			if (seconds < 0) seconds = 0;
			var tiltEase = tiltParts.length > 1 && tiltParts[1].trim().length > 0 ? tiltParts[1].trim() : 'quadInOut';
			addChartCameraEvent(event, {time: event.time, track: 'tilt', x: 0, y: 0, zoom: defaultZoom, duration: seconds * 1000, ease: tiltEase, target: -1, angle: angle}, 'tilt');
		}
		else if (name == 'add camera zoom')
		{
			var increment = Std.parseFloat(event.value1);
			if (Math.isNaN(increment)) increment = 0.015;
			var hudIncrement = event.value2 == null ? Math.NaN : Std.parseFloat(event.value2);
			if (Math.isNaN(hudIncrement)) hudIncrement = increment * 2;
			addChartCameraEvent(event, {time: event.time, track: 'kick', x: 0, y: 0, zoom: increment, hudZoom: hudIncrement, duration: 0, ease: 'linear', target: -1}, 'kick');
		}
		else if (name == 'set camzoom' || name == 'set camera zoom' || name == 'defaultcamzoom')
		{
			var zoom = Std.parseFloat(event.value1);
			if (Math.isNaN(zoom) || zoom <= 0) return;
			var seconds = Std.parseFloat(event.value2);
			if (Math.isNaN(seconds) || seconds <= 0) seconds = 0;
			addChartCameraEvent(event, {time: event.time, track: 'zoom', x: 0, y: 0, zoom: zoom, duration: seconds * 1000, ease: 'sineInOut', target: -1}, 'zoom');
		}
		else if (name == 'camera control')
		{
			var coordinates = event.value1 == null ? [] : event.value1.split(',');
			if (coordinates.length >= 2)
			{
				var base = chartCameraAt(event.time);
				var x = Std.parseFloat(coordinates[0]);
				var y = Std.parseFloat(coordinates[1]);
				if (Math.isNaN(x)) x = base.x;
				if (Math.isNaN(y)) y = base.y;
				addChartCameraEvent(event, {time: event.time, track: 'focus', x: x, y: y, zoom: defaultZoom, duration: 0, ease: 'linear', target: -1}, 'focus');
			}
			var zoom = Std.parseFloat(event.value2);
			if (!Math.isNaN(zoom) && zoom > 0)
				addChartCameraEvent(event, {time: event.time, track: 'zoom', x: 0, y: 0, zoom: zoom, duration: 0, ease: 'linear', target: -1}, 'zoom');
		}
	}

	function rebuildCameraEventCache():Void
	{
		if (!cameraEventCacheDirty) return;
		var visibleChartKeys:Array<CamEvent> = [];
		for (link in chartCameraLinks)
			if (chartCameraLinkVisible(link)) visibleChartKeys.push(link.camera);
		sortedCameraEvents = visibleChartKeys.concat(events);
		sortedCameraEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		focusCameraEvents = [];
		focusReleaseEvents = [];
		zoomCameraEvents = [];
		tiltCameraEvents = [];
		zoomKickEvents = [];
		for (event in sortedCameraEvents)
			switch (event.track)
			{
				case 'focus', 'general':
					focusCameraEvents.push(event);
					if (event.target == -2) focusReleaseEvents.push(event);
				case 'zoom': zoomCameraEvents.push(event);
				case 'tilt': tiltCameraEvents.push(event);
				case 'kick': zoomKickEvents.push(event);
			}
		cameraEventCacheDirty = false;
	}

	function buildSectionCameraCache():Void
	{
		sectionCameraTargets = [];
		sectionWho = [];
		sectionEnds = [];
		if (PlayState.SONG == null || PlayState.SONG.notes == null) return;
		var bpm:Float = PlayState.SONG.bpm > 0 ? PlayState.SONG.bpm : 100;
		var sectionStart:Float = 0;
		for (section in PlayState.SONG.notes)
		{
			if (section == null) continue;
			if (section.changeBPM && section.bpm > 0) bpm = section.bpm;
			var who:Int = section.gfSection && previewCharacters[2] != null ? 2 : (section.mustHitSection ? 0 : 1);
			var target = who >= 0 && who < charPos.length ? charPos[who] : defaultCam;
			sectionCameraTargets.push({time: sectionStart, x: target[0], y: target[1]});
			sectionWho.push(who);
			var beats:Float = section.sectionBeats > 0 ? section.sectionBeats : 4;
			sectionStart += beats * 60000 / bpm;
			sectionEnds.push(sectionStart);
		}
	}

	function chartFocusActive(time:Float):Bool
	{
		rebuildCameraEventCache();
		var end = upperBoundCameraEvents(focusCameraEvents, time);
		if (end <= 0) return false;
		var latest = focusCameraEvents[end - 1];
		if (latest.target == -2) return false;
		if (latest.autoRelease == true && time >= latest.time + Math.max(0, latest.duration)) return false;
		var releaseCount = upperBoundCameraEvents(focusReleaseEvents, time);
		return releaseCount <= 0 || latest.time > focusReleaseEvents[releaseCount - 1].time;
	}

	function chartZoomActive(time:Float):Bool
	{
		rebuildCameraEventCache();
		// Add Camera Zoom is an impulse with a decay tail, not a persistent camera
		// override. Only explicit zoom tracks own the camera after their event starts.
		return upperBoundCameraEvents(zoomCameraEvents, time) > 0;
	}

	function upperBoundCameraEvents(list:Array<CamEvent>, time:Float):Int
	{
		var low = 0;
		var high = list.length;
		while (low < high)
		{
			var mid = (low + high) >>> 1;
			if (list[mid].time <= time) low = mid + 1;
			else high = mid;
		}
		return low;
	}

	// =====================================================================
	//  Camera evaluation (ใช้ตรรกะเดียวกันนี้ใน PlayState ได้)
	// =====================================================================
	function resolveXY(e:CamEvent):Array<Float>
	{
		if (e.target >= 0 && e.target < charPos.length)
		{
			var base = charPos[e.target];
			var link = chartCameraLinkFor(e);
			var gfTargetOffset = link != null && link.source.name.toLowerCase() == 'target camera' && e.target == 2;
			return [base[0] + e.x - (gfTargetOffset ? stageCameraOffsets[2][0] * 2 : 0), base[1] + e.y - (gfTargetOffset ? stageCameraOffsets[2][1] * 2 : 0)];
		}
		return [e.x, e.y];
	}

	inline function resolveX(e:CamEvent):Float
	{
		if (e.target < 0 || e.target >= charPos.length) return e.x;
		var link = chartCameraLinkFor(e);
		var gfTargetOffset = link != null && link.source.name.toLowerCase() == 'target camera' && e.target == 2;
		return charPos[e.target][0] + e.x - (gfTargetOffset ? stageCameraOffsets[2][0] * 2 : 0);
	}

	inline function resolveY(e:CamEvent):Float
	{
		if (e.target < 0 || e.target >= charPos.length) return e.y;
		var link = chartCameraLinkFor(e);
		var gfTargetOffset = link != null && link.source.name.toLowerCase() == 'target camera' && e.target == 2;
		return charPos[e.target][1] + e.y - (gfTargetOffset ? stageCameraOffsets[2][1] * 2 : 0);
	}

	function easeFn(name:String):Float->Float
	{
		if (easeCache.exists(name)) return easeCache.get(name);
		var f:Dynamic = Reflect.getProperty(FlxEase, name);
		if (f == null) return FlxEase.linear;
		var result:Float->Float = cast f;
		easeCache.set(name, result);
		return result;
	}

	function interpolateValue(from:Float, to:Float, at:Float, startTime:Float, duration:Float, easeName:String):Float
	{
		if (duration <= 0 || at >= startTime + duration) return to;
		if (at <= startTime) return from;
		var progress = Math.max(0, Math.min(1, (at - startTime) / duration));
		return from + (to - from) * easeFn(easeName)(progress);
	}

	/** Approximate the real gameplay camera target when the chart changes sections.
	 *  PlayState changes camFollow at each section and FlxCamera.followLerp pans toward it;
	 *  reconstruct the same target changes for arbitrary Timeline seeks. Explicit Focus events
	 *  take over from their start time, matching isCameraOnForcedPos in PlayState. */
	function chartCameraAt(t:Float):{x:Float, y:Float}
	{
		if (sectionCameraTargets.length == 0)
		{
			chartCameraPointScratch.x = defaultCam[0];
			chartCameraPointScratch.y = defaultCam[1];
			return chartCameraPointScratch;
		}
		var low = 0;
		var high = sectionCameraTargets.length;
		while (low < high)
		{
			var mid = (low + high) >>> 1;
			if (sectionCameraTargets[mid].time <= t) low = mid + 1;
			else high = mid;
		}
		var target = sectionCameraTargets[low > 0 ? low - 1 : 0];
		chartCameraPointScratch.x = target.x;
		chartCameraPointScratch.y = target.y;
		return chartCameraPointScratch;
	}

	/** มุมกล้อง (Tilt, องศา) ณ เวลา t: ไล่ต่อจาก key ก่อนหน้า (เหมือนแทร็ก Zoom) ก่อน key แรก = 0 */
	function evalAngleAt(t:Float):Float
	{
		rebuildCameraEventCache();
		var fromA:Float = 0, toA:Float = 0;
		var start:Float = 0, dur:Float = 0;
		var easeName:String = 'linear';
		var end = upperBoundCameraEvents(tiltCameraEvents, t);
		for (i in 0...end)
		{
			var e = tiltCameraEvents[i];
			fromA = interpolateValue(fromA, toA, e.time, start, dur, easeName);
			toA = angleOf(e);
			start = e.time;
			dur = e.duration;
			easeName = e.ease;
		}
		return interpolateValue(fromA, toA, t, start, dur, easeName);
	}

	/** timeline คุมมุมกล้องตั้งแต่ Tilt key แรก (ทั้งตอนเล่นและตอนหยุด) ก่อนถึง key แรกมุมเป็นของ PlayState / สคริปต์ตามเดิม */
	function applyTimelineTilt():Void
	{
		if (previewCamera == null) return;
		rebuildCameraEventCache();
		if (upperBoundCameraEvents(tiltCameraEvents, songPos) <= 0)
		{
			if (tiltWasOwned)
			{
				tiltWasOwned = false;
				previewCamera.angle = 0;
			}
			return;
		}
		tiltWasOwned = true;
		previewCamera.angle = evalAngleAt(songPos);
	}

	public function evalAt(t:Float):{x:Float, y:Float, zoom:Float}
	{
		rebuildCameraEventCache();
		var base = chartCameraAt(t);
		var cx:Float = base.x;
		var cy:Float = base.y;

		// A blank Camera Follow Pos releases the forced target and resumes section
		// following. Binary searches avoid allocating/scanning the whole track per frame.
		var focusEndIndex = upperBoundCameraEvents(focusCameraEvents, t);
		var firstFocusIndex = 0;
		// Explicit Release keys and Auto-release durations are virtual boundaries; don't require an extra timeline key.
		for (i in 0...focusEndIndex)
		{
			var boundary = focusCameraEvents[i];
			if (boundary.target == -2 || (boundary.autoRelease == true && t >= boundary.time + Math.max(0, boundary.duration)))
				firstFocusIndex = i + 1;
		}
		if (firstFocusIndex < focusEndIndex)
		{
			var first = focusCameraEvents[firstFocusIndex];
			var baseAtFirst = chartCameraAt(first.time);
			var fromX:Float = baseAtFirst.x, fromY:Float = baseAtFirst.y;
			var toX:Float = fromX, toY:Float = fromY;
			var focusStart:Float = first.time;
			var focusDuration:Float = first.duration;
			var focusEase:String = first.ease;
			toX = resolveX(first); toY = resolveY(first);
			for (i in (firstFocusIndex + 1)...focusEndIndex)
			{
				var e = focusCameraEvents[i];
				fromX = interpolateValue(fromX, toX, e.time, focusStart, focusDuration, focusEase);
				fromY = interpolateValue(fromY, toY, e.time, focusStart, focusDuration, focusEase);
				toX = resolveX(e); toY = resolveY(e);
				focusStart = e.time; focusDuration = e.duration; focusEase = e.ease;
			}
			cx = interpolateValue(fromX, toX, t, focusStart, focusDuration, focusEase);
			cy = interpolateValue(fromY, toY, t, focusStart, focusDuration, focusEase);
		}

		var fromZoom:Float = defaultZoom, toZoom:Float = defaultZoom;
		var zoomStart:Float = 0, zoomDuration:Float = 0, zoomEase:String = "linear";
		var zoomEndIndex = upperBoundCameraEvents(zoomCameraEvents, t);
		for (i in 0...zoomEndIndex)
		{
			var e = zoomCameraEvents[i];
			fromZoom = interpolateValue(fromZoom, toZoom, e.time, zoomStart, zoomDuration, zoomEase);
			toZoom = e.zoom;
			zoomStart = e.time; zoomDuration = e.duration; zoomEase = e.ease;
		}
		var cz = interpolateValue(fromZoom, toZoom, t, zoomStart, zoomDuration, zoomEase);
		// Keep the live PlayState camera state in sync with the
		// gameplay default zoom, while additive beat/event impulses remain separate.
		if (stageHost != null) stageHost.defaultCamZoom = cz;
		var zoomDecay:Float = previewZoomDecayAt(t);
		if (stageHost != null) stageHost.camZoomingDecay = zoomDecay;
		var gameplayBopping = ClientPrefs.data.camZooms && stageHost != null && stageHost.camZooming;
		var kickEndIndex = upperBoundCameraEvents(zoomKickEvents, t);
		var kickIndex = kickEndIndex - 1;
		while (kickIndex >= 0 && (!gameplayBopping || t - zoomKickEvents[kickIndex].time <= 3000))
		{
			var kick = zoomKickEvents[kickIndex];
			if (ClientPrefs.data.camZooms && cz < 1.35)
				cz += gameplayBopping ? kick.zoom * Math.exp(-3.125 * zoomDecay * (t - kick.time) / 1000) : kick.zoom;
			kickIndex--;
		}

		// Match PlayState's beat zoom after the first chart note enables camZooming.
		// Only inspect the few recent beats that still have a visible decay tail.
		if (gameplayBopping && songName != 'tutorial' && firstChartNoteTime != Math.POSITIVE_INFINITY && t >= firstChartNoteTime)
		{
			var beat:Int = Conductor.getBeatRounded(t);
			var firstBeat:Int = Conductor.getBeatRounded(firstChartNoteTime);
			while (beat >= firstBeat)
			{
				var beatTime:Float = Conductor.beatToSeconds(beat);
				var sinceBeat:Float = t - beatTime;
				if (sinceBeat > 3000) break;
				if (sinceBeat >= 0 && beatTime >= firstChartNoteTime && cz < 1.35)
				{
					var bop = cameraBopSettingsAt(beatTime);
					if (bop.frequency > 0 && beat % bop.frequency == 0)
						cz += 0.015 * bop.multiplier * Math.exp(-3.125 * zoomDecay * sinceBeat / 1000);
				}
				beat--;
			}

			// PlayState also adds one zoom on section boundaries that do not coincide
			// with the configured camera-bop frequency.
			for (section in sectionCameraTargets)
			{
				var sinceSection:Float = t - section.time;
				if (sinceSection < 0 || sinceSection > 3000 || section.time < firstChartNoteTime) continue;
				var sectionBeat = Conductor.getBeatRounded(section.time);
				var bop = cameraBopSettingsAt(section.time);
				if (bop.frequency > 0 && sectionBeat % bop.frequency != 0 && cz < 1.35)
					cz += 0.015 * bop.multiplier * Math.exp(-3.125 * zoomDecay * sinceSection / 1000);
			}
		}
		cameraEvalScratch.x = cx;
		cameraEvalScratch.y = cy;
		cameraEvalScratch.zoom = cz;
		return cameraEvalScratch;
	}

	/** จัดมุมมองให้เห็นกรอบ VCam ทั้งกรอบพอดี preview */
	function fitPreview():Void
	{
		var cam = vcamPose;
		var lens = cameraLensSize();
		var lensWidth = extendedBounds ? lens.height * (20 / 9) : lens.width;
		var fit = Math.min(pvW / Math.max(1, lensWidth), pvH / Math.max(1, lens.height)) * 0.94;
		viewCenterX = cam.x;
		viewCenterY = cam.y;
		// Relative: scale = zoom ของ VCam x viewZoom, Free: scale = viewZoom
		viewZoom = relativeView ? fit : fit * Math.max(0.01, cam.zoom);
	}

	/** The gameplay camera's logical viewport, independent from the editor's cropped preview. */
	function cameraLensSize():{width:Float, height:Float}
	{
		cameraLensScratch.width = FlxG.width;
		cameraLensScratch.height = FlxG.height;
		// FlxG.camera คือ camGame ที่ editor ย่อให้เท่าพรีวิว (PREV_W x previewPanelHeight()) ใช้เป็นเลนส์ไม่ได้ ต้องใช้ขนาดจริงที่ผู้เล่นเห็น
		if (originalGameCameraWidth > 0 && originalGameCameraHeight > 0)
		{
			cameraLensScratch.width = originalGameCameraWidth;
			cameraLensScratch.height = originalGameCameraHeight;
		}
		return cameraLensScratch;
	}

	/** Project the real gameplay camera bounds into the current preview viewport. */
	function cameraFrameRect(camera:{x:Float, y:Float, zoom:Float}):{x:Float, y:Float, width:Float, height:Float}
	{
		var lens = cameraLensSize();
		var scale = previewScale();
		var lensWidth = extendedBounds ? lens.height * (20 / 9) : lens.width;
		var zoom = Math.max(0.01, camera.zoom);
		var width = lensWidth * scale / zoom;
		var height = lens.height * scale / zoom;
		var x = pvX + pvW * 0.5 + (camera.x - viewCenterX) * scale - width * 0.5;
		var y = pvY + pvH * 0.5 + (camera.y - viewCenterY) * scale - height * 0.5;
		cameraFrameScratch.x = x;
		cameraFrameScratch.y = y;
		cameraFrameScratch.width = width;
		cameraFrameScratch.height = height;
		return cameraFrameScratch;
	}

	/** Return the active state for View menu toggles; -1 means the row is an action. */
	function viewToggleState(label:String):Int
	{
		return switch (label)
		{
			case 'Toggle Relative View': relativeView ? 1 : 0;
			case 'Toggle Camera Preview': showCameraFrame ? 1 : 0;
			case 'Show Extended Bounds': extendedBounds ? 1 : 0;
			case 'Toggle Passepartout': passepartout ? 1 : 0;
			case 'Toggle Camera Zooms': ClientPrefs.data.camZooms ? 1 : 0;
			case 'Disable Song Lua': disableSongLua ? 1 : 0;
			case 'Toggle Snap': snapEnabled ? 1 : 0;
			default: -1;
		};
	}

	#if LUA_ALLOWED
	/**
	 * Lua ของ "เพลงนี้" เท่านั้น = สคริปต์ .lua ที่อยู่ในโฟลเดอร์ data/<เพลง>/ (หรือโฟลเดอร์เดียวกับไฟล์ chart ที่เปิดอยู่)
	 * ไม่นับ scripts/, custom_events/, custom_notetypes/, stages/, characters/ และ Lua ของเพลงอื่น
	 */
	function isCurrentSongLua(path:String):Bool
	{
		if (path == null || PlayState.SONG == null) return false;
		var n = path.split('\\').join('/').toLowerCase();
		if (!camEndsWith(n, '.lua')) return false;
		for (other in ['/scripts/', '/custom_events/', '/custom_notetypes/', '/stages/', '/characters/'])
			if (camContains(n, other) || camStartsWith(n, other.substr(1))) return false;
		var slug = Paths.formatToSongPath(Std.string(PlayState.SONG.song)).toLowerCase();
		if (slug.length > 0 && (camContains(n, '/data/' + slug + '/') || camStartsWith(n, 'data/' + slug + '/'))) return true;
		var chartDir = selectedChartDirectory();
		if (chartDir != null && chartDir.length > 0)
		{
			var dir = chartDir.split('\\').join('/').toLowerCase();
			if (!camEndsWith(dir, '/')) dir += '/';
			if (camStartsWith(n, dir) && camContains(dir, '/data/')) return true;
		}
		return false;
	}
	#end

	/** ปิด/เปิด Lua ของเพลงนี้โดยพักสคริปต์ออกจาก luaArray (ไม่โดน callback) Lua อื่นทั้งหมดยังทำงานตามเดิม */
	function applySongLuaSetting():Void
	{
		#if LUA_ALLOWED
		if (luaArray == null) return;
		if (disableSongLua)
		{
			var i = luaArray.length;
			while (i-- > 0)
			{
				var script = luaArray[i];
				if (script == null || script.closed || !isCurrentSongLua(script.scriptName)) continue;
				luaArray.remove(script);
				stashedSongLuas.push(script);
			}
		}
		else if (stashedSongLuas.length > 0)
		{
			for (script in stashedSongLuas)
				if (!script.closed && !luaArray.contains(script)) luaArray.push(script);
			stashedSongLuas = [];
		}
		#end
	}

	function toggleSongLua():Void
	{
		disableSongLua = !disableSongLua;
		applySongLuaSetting();
		status(disableSongLua ? 'ปิด Lua ของเพลงนี้แล้ว (scripts/, custom_events, notetypes, stage, character ยังทำงาน) สิ่งที่ onCreate สร้างไว้แล้วจะยังอยู่' : 'เปิด Lua ของเพลงอีกครั้ง');
	}

	function toggleCameraZooms():Void
	{
		ClientPrefs.data.camZooms = !ClientPrefs.data.camZooms;
		ClientPrefs.saveSettings();
		status('Camera zooms ' + (ClientPrefs.data.camZooms ? 'On' : 'Off'));
	}

	function drawMenuCheck(x:Float, y:Float, checked:Bool):Void
	{
		frameRect(x, y, 12, 12, checked ? 0xFF70C8D6 : 0xFF737D89, 1);
		if (!checked) return;
		// Pixel-drawn check mark works with every bundled font and keeps menu rows aligned.
		rect(x + 2, y + 5, 2, 2, 0xFFBDF7FF);
		rect(x + 4, y + 7, 2, 2, 0xFFBDF7FF);
		rect(x + 6, y + 5, 2, 2, 0xFFBDF7FF);
		rect(x + 8, y + 3, 2, 2, 0xFFBDF7FF);
	}

	function previewSectionAt(time:Float):Int
	{
		if (PlayState.SONG == null || PlayState.SONG.notes == null || PlayState.SONG.notes.length == 0) return 0;
		var bpm:Float = PlayState.SONG.bpm > 0 ? PlayState.SONG.bpm : 100;
		var sectionStart:Float = 0;
		for (i in 0...PlayState.SONG.notes.length)
		{
			var section:Dynamic = PlayState.SONG.notes[i];
			if (section.changeBPM && section.bpm > 0) bpm = section.bpm;
			var beats:Float = section.sectionBeats > 0 ? section.sectionBeats : 4;
			var end = sectionStart + beats * 60000 / bpm;
			if (time < end) return i;
			sectionStart = end;
		}
		return PlayState.SONG.notes.length - 1;
	}

	inline function previewBlockedNoteKey(time:Float, lane:Int, playerSide:Bool, noteType:String):String
	{
		var normalizedType = noteType == null ? '' : noteType.trim().toLowerCase();
		return Std.string(Std.int(Math.round(time))) + ':' + lane + ':' + (playerSide ? 'p' : 'o') + ':' + normalizedType;
	}

	/**
	 * In Camera Editor botplay, never auto-hit a player note that is explicitly ignored,
	 * blocked, or marked as causing a miss. Cache the key before invalidating it because
	 * updatePreviewChartScripts runs after PlayState.update() and also simulates script hits.
	 */
	override public function goodNoteHit(note:Note):Void
	{
		if (cameraEditorMode && cpuControlled && note != null && note.mustPress
			&& (note.ignoreNote || note.hitCausesMiss || note.blockHit))
		{
			blockedPreviewNoteKeys.set(previewBlockedNoteKey(note.strumTime, Std.int(Math.abs(note.noteData) % 4), true, note.noteType), true);
			// Removing the note prevents repeated botplay attempts and also prevents hurt/miss effects.
			invalidateNote(note);
			return;
		}
		super.goodNoteHit(note);
	}

	/** Check native note flags as well as the cache set by goodNoteHit(). */
	function isPreviewNoteBlocked(note:PreviewNote):Bool
	{
		if (note == null || !note.playerSide) return false;
		if (blockedPreviewNoteKeys.exists(previewBlockedNoteKey(note.time, note.lane, true, note.noteType))) return true;
		if (note.noteType != null && note.noteType.trim().toLowerCase() == 'hurt note') return true;
		var noteType = note.noteType == null ? '' : note.noteType.trim().toLowerCase();
		if (notes != null)
			for (nativeNote in notes.members)
				if (nativeNote != null && nativeNote.mustPress && Math.abs(nativeNote.strumTime - note.time) <= 1.5
					&& Math.abs(nativeNote.noteData) % 4 == note.lane
					&& (nativeNote.noteType == null ? '' : nativeNote.noteType.trim().toLowerCase()) == noteType
					&& (nativeNote.ignoreNote || nativeNote.hitCausesMiss || nativeNote.blockHit)) return true;
		if (unspawnNotes != null)
			for (nativeNote in unspawnNotes)
				if (nativeNote != null && nativeNote.mustPress && Math.abs(nativeNote.strumTime - note.time) <= 1.5
					&& Math.abs(nativeNote.noteData) % 4 == note.lane
					&& (nativeNote.noteType == null ? '' : nativeNote.noteType.trim().toLowerCase()) == noteType
					&& (nativeNote.ignoreNote || nativeNote.hitCausesMiss || nativeNote.blockHit)) return true;
		return false;
	}

	function dispatchPreviewNote(index:Int, isSustain:Bool):Void
	{
		if (stageHost == null || index < 0 || index >= previewNotes.length) return;
		var note = previewNotes[index];
		if (isPreviewNoteBlocked(note)) return;
		var callback = note.playerSide ? 'goodNoteHit' : 'opponentNoteHit';
		var args:Array<Dynamic> = [index, note.lane, note.noteType, isSustain];
		#if LUA_ALLOWED
		try stageHost.callOnLuas(callback, args) catch (e:Dynamic) trace('Camera Editor $callback: $e');
		#end
		#if HSCRIPT_ALLOWED
		try stageHost.callOnHScript('onPreviewNoteHit', [note.playerSide, note.lane, note.noteType, isSustain, note.time]) catch (e:Dynamic)
			trace('Camera Editor onPreviewNoteHit: $e');
		#end
		try stageHost.callOnScripts('onNoteHit', [note.playerSide, note.lane, note.noteType, isSustain, note.time]) catch (e:Dynamic)
			trace('Camera Editor onNoteHit: $e');
	}

	function cameraIsForcedByScript():Bool
		return stageHost != null && Reflect.field(stageHost, 'isCameraOnForcedPos') == true;

	function capturePreviewScriptCameraChanges(beforeX:Float, beforeY:Float, beforeZoom:Float, beforeDefaultZoom:Float):Void
	{
		if (stageHost == null || stageHost.camFollow == null) return;
		var forced = cameraIsForcedByScript();
		if (forced)
		{
			scriptCameraForced = true;
			scriptCameraFollowOverride = true;
		}
		else if (scriptCameraForced)
		{
			scriptCameraForced = false;
			scriptCameraFollowOverride = false;
		}
		else if (Math.abs(stageHost.camFollow.x - beforeX) > 0.01 || Math.abs(stageHost.camFollow.y - beforeY) > 0.01)
			scriptCameraFollowOverride = true;

		if (Math.abs(FlxG.camera.zoom - beforeZoom) > 0.001 || Math.abs(stageHost.defaultCamZoom - beforeDefaultZoom) > 0.001)
			scriptCameraZoomOverride = true;
	}

	/** Stop a chart-event video without using PlayState.videoCutscene or changing song/gameplay flags. */
	function stopPreviewEventVideo():Void
	{
		#if VIDEOS_ALLOWED
		var oldVideo = previewEventVideo;
		previewEventVideo = null;
		previewEventVideoTime = -1;
		if (oldVideo != null)
		{
			try oldVideo.pause() catch (_:Dynamic) {}
			try oldVideo.destroy() catch (_:Dynamic) {}
		}
		#else
		previewEventVideo = null;
		previewEventVideoTime = -1;
		#end
	}

	/** Fit the video as a screen-space overlay exactly inside the visible preview frame. */
	function fitPreviewEventVideo(video:VideoSprite):Void
	{
		#if VIDEOS_ALLOWED
		if (video == null || video.videoSprite == null) return;
		video.videoSprite.setGraphicSize(pvW, pvH);
		video.videoSprite.updateHitbox();
		video.videoSprite.setPosition(pvX, pvY);
		video.videoSprite.scrollFactor.set(0, 0);
		if (editorUICamera != null) video.videoSprite.cameras = [editorUICamera];
		#end
	}

	/** Camera Editor-only preview for Play Video. `value2` accepts game/camGame, hud/camHUD, or other/camOther.
	 *  The HUD camera itself is intentionally hidden in this editor, so a HUD video is composited into the
	 *  preview rectangle on the editor UI camera instead. This keeps it screen-aligned and does not touch
	 *  the real gameplay camera, cutscene flags, music, or `videoCutscene`. */
	function showPreviewEventVideo(videoName:String, cameraName:String, strumTime:Float):Void
	{
		#if VIDEOS_ALLOWED
		var clipName = videoName == null ? '' : videoName.trim();
		if (clipName.length == 0) return;
		stopPreviewEventVideo();
		var fileName = Paths.video(clipName);
		var foundFile:Bool = false;
		#if sys
		if (NativeFileSystem.exists(fileName))
		#else
		if (openfl.Assets.exists(fileName))
		#end
		foundFile = true;
		if (!foundFile)
		{
			if (statusText != null) status('Video not found: ' + fileName);
			return;
		}

		var requestedCamera = cameraName == null ? '' : cameraName.trim().toLowerCase();
		if (requestedCamera.length == 0) requestedCamera = 'hud';
		previewEventVideoCamera = requestedCamera;
		var cameraLabel:String = switch (requestedCamera)
		{
			case 'hud' | 'camhud' | 'cam hud' | '1': 'HUD';
			case 'game' | 'camgame' | 'cam game' | 'stage' | '0': 'Game';
			case 'other' | 'camother' | 'cam other' | '2': 'Other';
			default: requestedCamera;
		};

		// `true` means waiting/in-game overlay: do not add the cutscene's opaque black cover.
		// canSkip=false prevents the video overlay from consuming gameplay input.
		var video = new VideoSprite(fileName, true, false, false);
		video.scrollFactor.set(0, 0);
		if (editorUICamera != null) video.cameras = [editorUICamera];
		if (video.videoSprite != null && editorUICamera != null)
			video.videoSprite.cameras = [editorUICamera];
		video.finishCallback = function():Void
		{
			if (previewEventVideo == video)
			{
				previewEventVideo = null;
				previewEventVideoTime = -1;
			}
		};
		previewEventVideo = video;
		previewEventVideoTime = strumTime;
		// Insert below the preview mask and editor controls, so the video is clipped to the
		// preview rectangle and never covers the timeline/buttons.
		var canvasIndex:Int = canvas == null ? -1 : members.indexOf(canvas);
		if (canvasIndex >= 0) insert(canvasIndex, video) else add(video);
		fitPreviewEventVideo(video);
		// VideoSprite's format callback initially scales to the full game window; this later
		// listener reapplies the Camera Editor's viewport bounds once the stream has a texture.
		if (video.videoSprite != null && video.videoSprite.bitmap != null)
			video.videoSprite.bitmap.onFormatSetup.add(function()
			{
				if (previewEventVideo != video) return;
				fitPreviewEventVideo(video);
				// When the user scrubs past this event while paused, show the frame matching
				// the playhead instead of restarting the clip from its first frame.
				var offsetMs:Float = Math.max(0, songPos - strumTime);
				if (offsetMs > 20)
					try video.videoSprite.bitmap.time = Std.int(offsetMs) catch (_:Dynamic) {}
				if (!playing) video.pause();
			});
		video.play();
		if (!playing) video.pause();
		if (statusText != null) status('Video Preview: ' + clipName + ' → ' + cameraLabel);
		#else
		if (statusText != null) status('Video preview requires VIDEOS_ALLOWED in the build');
		#end
	}

	function applyPreviewChartEvent(event:PreviewChartEvent):Void
	{
		if (stageHost == null) return;
		var beforeFollowX = stageHost.camFollow == null ? 0 : stageHost.camFollow.x;
		var beforeFollowY = stageHost.camFollow == null ? 0 : stageHost.camFollow.y;
		var beforeZoom = FlxG.camera.zoom;
		var beforeDefaultZoom = stageHost.defaultCamZoom;
		var name = event.name == null ? '' : event.name;
		var lower = name.toLowerCase();
		var value1 = event.value1 == null ? '' : event.value1;
		var value2 = event.value2 == null ? '' : event.value2;
		// These built-in camera tracks are evaluated by the timeline below. Custom camera
		// events are executed by Lua/HScript, so let their camera writes remain authoritative.
		switch (lower)
		{
			case 'focuscamera' | 'focus camera' | 'camera follow pos' | 'camera warp pos':
				scriptCameraFollowOverride = false;
				scriptCameraForced = false;
				@:privateAccess stageHost.isCameraOnForcedPos = false;
			case 'target camera':
				scriptCameraFollowOverride = false;
				scriptCameraForced = false;
				@:privateAccess stageHost.isCameraOnForcedPos = false;
			case 'rol cam' | 'roll camera':
				// Tilt เป็นของ timeline: ไม่ต้องถือว่าสคริปต์ยึดกล้อง (Lua ยังทำงานตามปกติ)
			case 'camera control':
				scriptCameraFollowOverride = false;
				scriptCameraForced = false;
				scriptCameraZoomOverride = false;
				@:privateAccess stageHost.isCameraOnForcedPos = false;
			case 'zoomcamera' | 'zoom camera' | 'add camera zoom' | 'set camzoom':
				scriptCameraZoomOverride = false;
			default:
				var isCameraEvent = camContains(lower, 'camera') || camContains(lower, 'cam') || camContains(lower, 'zoom')
					|| camContains(lower, 'focus') || camContains(lower, 'follow');
				if (isCameraEvent && !camContains(lower, 'shake'))
				{
					scriptCameraFollowOverride = true;
					scriptCameraZoomOverride = true;
				}
		}
		// Use the same native event implementation as gameplay. The preview flag leaves
		// timeline-owned camera changes on the editor's single camera-event evaluator.
		try stageHost.triggerEvent(name, value1, value2, event.time, true) catch (e:Dynamic) trace('Camera Editor event $name: $e');
		capturePreviewScriptCameraChanges(beforeFollowX, beforeFollowY, beforeZoom, beforeDefaultZoom);
		if (lower == 'change character') syncPreviewCharactersFromHost();
		// Built-in events have native timeline equivalents. Lua callbacks still run, but
		// their temporary writes must not pin the preview to the previous camera target.
		switch (lower)
		{
			case 'focuscamera' | 'focus camera' | 'camera follow pos' | 'camera warp pos' | 'target camera':
				scriptCameraFollowOverride = false;
				scriptCameraForced = false;
				@:privateAccess stageHost.isCameraOnForcedPos = false;
			case 'zoomcamera' | 'zoom camera' | 'add camera zoom' | 'set camzoom' | 'camera control':
				scriptCameraZoomOverride = false;
		}
	}

	function updatePreviewChartScripts(previousTime:Float):Void
	{
		if (stageHost == null || PlayState.SONG == null) return;
		var stepNow = Std.int(Math.floor(Conductor.getStepRounded(songPos)));
		var sectionNow = previewSectionAt(songPos);
		if (songPos < previousTime || Math.abs(songPos - previousTime) > 1000)
		{
			scriptNoteCursor = 0;
			while (scriptNoteCursor < previewNotes.length && previewNotes[scriptNoteCursor].time <= songPos) scriptNoteCursor++;
			previewChartEventCursor = 0;
			while (previewChartEventCursor < previewChartEvents.length && previewChartEvents[previewChartEventCursor].time <= songPos) previewChartEventCursor++;
			lastScriptStep = stepNow - 1;
			lastScriptBeat = Std.int(Math.floor(stepNow / 4)) - 1;
			lastScriptSection = sectionNow - 1;
			syncPreviewBoppingState(songPos);
			return;
		}
		if (songName != 'tutorial' && previewNotes.length > 0 && previewNotes[0].time <= songPos)
			stageHost.camZooming = true;

		while (scriptNoteCursor < previewNotes.length && previewNotes[scriptNoteCursor].time <= songPos)
		{
			var note = previewNotes[scriptNoteCursor];
			if (note.time > previousTime)
			{
				dispatchPreviewNote(scriptNoteCursor, false);
				var sustainStep = Conductor.getCrotchetAtTime(note.time) / 4;
				var holdEnd = note.time + note.sustain;
				var tick = note.time + sustainStep;
				while (note.sustain > 0 && tick <= holdEnd && tick <= songPos)
				{
					if (tick > previousTime) dispatchPreviewNote(scriptNoteCursor, true);
					tick += sustainStep;
				}
			}
			scriptNoteCursor++;
		}
		while (previewChartEventCursor < previewChartEvents.length && previewChartEvents[previewChartEventCursor].time <= songPos)
		{
			var event = previewChartEvents[previewChartEventCursor++];
			if (event.time > previousTime) applyPreviewChartEvent(event);
		}

		if (lastScriptStep < 0) lastScriptStep = stepNow - 1;
		if (stepNow > lastScriptStep)
			for (step in (lastScriptStep + 1)...(stepNow + 1))
			{
				stageHost.setOnScripts('curStep', step);
				try stageHost.callOnScripts('onStepHit') catch (e:Dynamic) trace('Camera Editor onStepHit: $e');
				var beat = Std.int(Math.floor(step / 4));
				if (step % 4 == 0 && beat > lastScriptBeat)
				{
					stageHost.setOnScripts('curBeat', beat);
					try stageHost.callOnScripts('onBeatHit') catch (e:Dynamic) trace('Camera Editor onBeatHit: $e');
					lastScriptBeat = beat;
				}
			}
		lastScriptStep = stepNow;
		if (sectionNow > lastScriptSection)
			for (section in (lastScriptSection + 1)...(sectionNow + 1))
			{
				stageHost.setOnScripts('curSection', section);
				var sectionData:Dynamic = null;
				if (PlayState.SONG.notes != null && section < PlayState.SONG.notes.length)
				{
					sectionData = PlayState.SONG.notes[section];
					stageHost.setOnScripts('mustHitSection', sectionData.mustHitSection);
					stageHost.setOnScripts('altAnim', sectionData.altAnim);
					stageHost.setOnScripts('gfSection', sectionData.gfSection);
				}

				// Use PlayState's section camera routine so onMoveCamera callbacks and
				// character camera offsets match gameplay. Explicit chart focus events and
				// script-forced positions keep control of the target until they release it.
				if (sectionData != null && !cameraIsForcedByScript() && !chartFocusActive(songPos))
				{
					var zoomBeforeMove = FlxG.camera.zoom;
					var defaultZoomBeforeMove = stageHost.defaultCamZoom;
					stageHost.moveCameraSection(section);
					// Keep arbitrary seeks aligned with the exact result of PlayState's
					// section callback, including stage-script onMoveCamera offsets.
					if (section >= 0 && section < sectionCameraTargets.length)
					{
						sectionCameraTargets[section].x = stageHost.camFollow.x;
						sectionCameraTargets[section].y = stageHost.camFollow.y;
					}
					var expected = chartCameraAt(songPos);
					scriptCameraFollowOverride = Math.abs(stageHost.camFollow.x - expected.x) > 1 || Math.abs(stageHost.camFollow.y - expected.y) > 1;
					if (Math.abs(FlxG.camera.zoom - zoomBeforeMove) > 0.001 || Math.abs(stageHost.defaultCamZoom - defaultZoomBeforeMove) > 0.001)
						scriptCameraZoomOverride = true;
				}
				var followBeforeSectionHitX = stageHost.camFollow.x;
				var followBeforeSectionHitY = stageHost.camFollow.y;
				var zoomBeforeSectionHit = FlxG.camera.zoom;
				var defaultZoomBeforeSectionHit = stageHost.defaultCamZoom;
				try stageHost.callOnScripts('onSectionHit') catch (e:Dynamic) trace('Camera Editor onSectionHit: $e');
				capturePreviewScriptCameraChanges(followBeforeSectionHitX, followBeforeSectionHitY, zoomBeforeSectionHit, defaultZoomBeforeSectionHit);
			}
		lastScriptSection = sectionNow;
	}

	// =====================================================================
	//  Commands (Undo / Redo)
	// =====================================================================
	function copyEv(e:CamEvent):CamEvent
		return {
			time: e.time, track: e.track, x: e.x, y: e.y, zoom: e.zoom,
			duration: e.duration, ease: e.ease, target: e.target, layer: layerOf(e), angle: angleOf(e), autoRelease: e.autoRelease == true, hudZoom: e.hudZoom
		};

	function applyEv(to:CamEvent, from:CamEvent)
	{
		to.time = from.time;
		to.track = from.track;
		to.x = from.x;
		to.y = from.y;
		to.zoom = from.zoom;
		to.duration = from.duration;
		to.ease = from.ease;
		to.target = from.target;
		to.layer = layerOf(from);
		to.angle = angleOf(from);
		to.autoRelease = from.autoRelease == true;
		to.hudZoom = from.hudZoom;
		sortEvents();
	}

	function sameEv(a:CamEvent, b:CamEvent):Bool
		return a.time == b.time && a.track == b.track && a.x == b.x && a.y == b.y && a.zoom == b.zoom && a.duration == b.duration && a.ease == b.ease
			&& a.target == b.target && layerOf(a) == layerOf(b) && angleOf(a) == angleOf(b)
			&& ((a.autoRelease == true) == (b.autoRelease == true)) && a.hudZoom == b.hudZoom;

	function sortEvents()
	{
		events.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		recountLayers();
		cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
		cameraEventListDirty = true;
		syncCameraEvents();
	}

	function syncCameraEvents():Void
	{
		if (cameraEditorMode)
			setCameraEditorEvents(events.filter(e -> e.track != 'tilt'), songPos); // Tilt ใช้ในตัว editor + export เป็น Rol cam เท่านั้น
	}

	function pushCmd(c:CamCmd, execute:Bool)
	{
		if (execute)
			c.run();
		history.push(c);
		if (history.length > MAX_UNDO_HISTORY)
			history.shift();
		redoStack = [];
	}

	function addEvent(e:CamEvent)
	{
		e.time = Math.max(0, Math.min(songLen, e.time));
		e.duration = Math.max(0, Math.min(songLen - e.time, e.duration));

		// One editable key per camera component at a timestamp. If the user adds a key
		// where an equivalent key already exists, update/select that key instead of stacking it.
		var existing:CamEvent = null;
		for (old in events)
			if (old != null && cameraTrackComponent(old.track) == cameraTrackComponent(e.track) && sameCameraEventTime(old.time, e.time))
			{
				existing = old;
				break;
			}
		if (existing != null)
		{
			var before = copyEv(existing);
			existing.time = e.time;
			existing.track = e.track;
			existing.x = e.x;
			existing.y = e.y;
			existing.zoom = e.zoom;
			existing.duration = e.duration;
			existing.ease = e.ease;
			existing.target = e.target;
			existing.layer = layerOf(e);
			existing.angle = angleOf(e);
			existing.autoRelease = e.autoRelease == true;
			selected = existing;
			selectedChartSource = null;
			selectedChartComponent = null;
			commitEdit(existing, before);
			sortEvents();
			refreshEventValueInputs();
			previewKey(existing);
			status('อัปเดต key กล้องเดิมที่ ' + fmtTime(existing.time));
			return;
		}

		var addCmd = new CamCmd(() ->
		{
			events.push(e);
			sortEvents();
		}, () ->
		{
			events.remove(e);
			cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
			cameraEventListDirty = true;
			syncCameraEvents();
			if (selected == e)
				selected = null;
		});
		addCmd.ev = e;
		pushCmd(addCmd, true);
		selected = e;
		selectedChartSource = null;
		selectedChartComponent = null;
		refreshEventValueInputs();
		previewKey(e);
	}

	function removeEvent(e:CamEvent)
	{
		var removeCmd = new CamCmd(() ->
		{
			events.remove(e);
			cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
			cameraEventListDirty = true;
			syncCameraEvents();
			if (selected == e)
			{
				selected = null;
				selectedChartSource = null;
				selectedChartComponent = null;
				refreshEventValueInputs();
			}
		}, () ->
		{
			events.push(e);
			sortEvents();
		});
		removeCmd.ev = e;
		pushCmd(removeCmd, true);
	}

	// เรียกหลังแก้ค่าของ ev ไปแล้ว โดยส่งสำเนาค่าเดิมมา
	function commitEdit(ev:CamEvent, old:CamEvent, merge:Bool = true)
	{
		var nw = copyEv(ev);
		if (sameEv(old, nw))
			return;
		var source:PreviewChartEvent = ev == selected ? selectedChartSource : null;
		var component = selectedChartComponent;
		var now = haxe.Timer.stamp() * 1000;

		// แก้ event เดิมต่อเนื่อง (กดลูกศรรัว ๆ, เลื่อน wheel) รวมเป็น undo สเต็ปเดียว
		var last = history.length > 0 ? history[history.length - 1] : null;
		if (merge && last != null && last.ev == ev && last.oldVal != null && redoStack.length == 0 && now - last.stamp < COALESCE_MS)
		{
			var original = last.oldVal;
			if (sameEv(original, nw))
			{
				// แก้กลับมาเป็นค่าเดิมแล้ว ไม่ต้องเหลือสเต็ปว่าง ๆ ใน history
				history.pop();
				if (source != null) applyChartCameraEdit(source, ev, original, component);
				else applyEv(ev, original);
				return;
			}
			var merged = makeEditCmd(ev, original, nw, source, component);
			history[history.length - 1] = merged;
			merged.run();
			return;
		}

		var cmd = makeEditCmd(ev, old, nw, source, component);
		pushCmd(cmd, false);
		if (source != null) applyChartCameraEdit(source, ev, nw, component);
	}

	function makeEditCmd(ev:CamEvent, from:CamEvent, to:CamEvent, source:PreviewChartEvent, component:String):CamCmd
	{
		var cmd = source != null
			? new CamCmd(() -> applyChartCameraEdit(source, ev, to, component), () -> applyChartCameraEdit(source, ev, from, component))
			: new CamCmd(() -> applyEv(ev, to), () -> applyEv(ev, from));
		cmd.ev = ev;
		cmd.oldVal = from;
		cmd.stamp = haxe.Timer.stamp() * 1000;
		return cmd;
	}

	/** หลัง Undo / Redo: เลือก event ที่เพิ่งเปลี่ยนกลับมา และล้าง selection ที่ชี้ไปยัง event ที่หายไปแล้ว */
	function afterHistory(c:CamCmd):Void
	{
		if (c.ev != null && (events.indexOf(c.ev) >= 0 || chartCameraEvents.indexOf(c.ev) >= 0))
		{
			selected = c.ev;
			selectedChartSource = sourceForChartCamera(c.ev);
		}
		else if (selected != null && events.indexOf(selected) < 0 && chartCameraEvents.indexOf(selected) < 0)
		{
			selected = null;
			selectedChartSource = null;
			selectedChartComponent = null;
		}
		cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
		cameraEventListDirty = true;
		refreshEventValueInputs();
	}

	function applyChartCameraEdit(source:PreviewChartEvent, camera:CamEvent, value:CamEvent, component:String):Void
	{
		applyEv(camera, value);
		if (source == null || source.rawSubEvent == null) return;

		var lower = source.name == null ? '' : source.name.toLowerCase();
		switch (lower)
		{
			case 'focuscamera' | 'focus camera' | 'target camera' | 'camera follow pos' | 'camera warp pos' | 'camera focus xy':
				// Normalize edited focus keys to the same built-in formats as the original Lua events:
				// character focus uses FocusCamera (steps/ease), custom tween uses Camera Focus XY,
				// zero-duration absolute position uses Camera Warp Pos, and release uses blank Follow Pos.
				var roundTo = function(v:Float):String return Std.string(Math.round(v * 100) / 100);
				if (camera.target == -2)
				{
					source.name = 'Camera Follow Pos';
					source.value1 = '';
					source.value2 = '';
				}
				else if (lower == 'target camera' && camera.target >= 0 && camera.target <= 2)
				{
					// Preserve old Target Camera's offset convention when editing legacy chart events.
					var targetName = camera.target == 0 ? 'bf' : (camera.target == 1 ? 'dad' : 'gf');
					var targetStepMs = Math.max(1, Conductor.getCrotchetAtTime(camera.time) / 4);
					var targetSteps = camera.duration <= 0 ? 0 : camera.duration / targetStepMs;
					source.value1 = targetName;
					source.value2 = timingWithAutoRelease('${roundTo(camera.x)},${roundTo(camera.y)},${roundTo(targetSteps)},${camera.ease}', camera.autoRelease == true);
				}
				else if (camera.target >= 0 && camera.target <= 2)
				{
					source.name = 'FocusCamera';
					var charName = camera.target == 0 ? 'bf' : (camera.target == 1 ? 'dad' : 'gf');
				source.value1 = (camera.x == 0 && camera.y == 0) ? charName : '$charName,${roundTo(camera.x)},${roundTo(camera.y)}';
					var focusStepMs = Math.max(1, Conductor.getCrotchetAtTime(camera.time) / 4);
					var focusTiming = camera.duration <= 0 ? (camera.autoRelease == true ? '0,linear' : '0') : '${roundTo(camera.duration / focusStepMs)},${camera.ease}';
					source.value2 = timingWithAutoRelease(focusTiming, camera.autoRelease == true);
				}
				else
				{
					var pos = resolveXY(camera);
					if (camera.duration > 0 || camera.autoRelease == true)
					{
						source.name = 'Camera Focus XY';
						var xyStepMs = Math.max(1, Conductor.getCrotchetAtTime(camera.time) / 4);
						source.value1 = '${roundTo(pos[0])},${roundTo(pos[1])}';
						var xyTiming = camera.duration <= 0 ? '0,linear' : '${roundTo(camera.duration / xyStepMs)},${camera.ease}';
						source.value2 = timingWithAutoRelease(xyTiming, camera.autoRelease == true);
					}
					else
					{
						source.name = 'Camera Warp Pos';
						source.value1 = roundTo(pos[0]);
						source.value2 = roundTo(pos[1]);
					}
				}
			case 'camera control':
				if (component == 'focus') source.value1 = '${camera.x},${camera.y}';
				else if (component == 'zoom') source.value2 = Std.string(camera.zoom);
			case 'zoomcamera' | 'zoom camera':
				if (lower == 'zoom camera')
				{
					var stepMs = Math.max(1, Conductor.getCrotchetAtTime(camera.time) / 4);
					source.value1 = '${camera.duration / stepMs},${camera.zoom / Math.max(0.01, defaultZoom)}';
					source.value2 = camera.ease;
				}
				else
				{
					source.value1 = Std.string(camera.zoom);
					source.value2 = '${camera.duration / 1000},${camera.ease}';
				}
			case 'rol cam' | 'roll camera':
				source.value1 = Std.string(Math.round(angleOf(camera) * 100) / 100);
				source.value2 = Std.string(Math.round(camera.duration) / 1000) + ',' + camera.ease;
			case 'add camera zoom': source.value1 = Std.string(camera.zoom);
			case 'set camzoom' | 'set camera zoom' | 'defaultcamzoom': source.value1 = Std.string(camera.zoom); source.value2 = Std.string(camera.duration / 1000);
		}

		if (source.rawRow != null && source.rawRow.length > 0)
		{
			source.rawRow[0] = Math.max(0, camera.time - ClientPrefs.data.noteOffset);
			var rowStrumTime:Float = source.rawRow[0] + ClientPrefs.data.noteOffset;
			if (PlayState.SONG != null && PlayState.SONG.events != null)
				PlayState.SONG.events.sort((a, b) ->
				{
					var ta = a != null && a.length > 0 && a[0] != null ? Std.parseFloat(Std.string(a[0])) : 0;
					var tb = b != null && b.length > 0 && b[0] != null ? Std.parseFloat(Std.string(b[0])) : 0;
					ta < tb ? -1 : (ta > tb ? 1 : 0);
				});
			for (other in previewChartEvents)
				if (other.rawRow == source.rawRow)
				{
					other.strumTime = rowStrumTime;
					recalculatePreviewChartEventTime(other);
				}
			for (link in chartCameraLinks)
				if (link.source.rawRow == source.rawRow) link.camera.time = link.source.time;
			rebuildPreviewBopEvents();
		}
		if (source.rawSubEvent.length < 1) source.rawSubEvent.push(source.name);
		else source.rawSubEvent[0] = source.name;
		if (source.rawSubEvent.length < 2) source.rawSubEvent.push(source.value1);
		else source.rawSubEvent[1] = source.value1;
		if (source.rawSubEvent.length < 3) source.rawSubEvent.push(source.value2);
		else source.rawSubEvent[2] = source.value2;

		syncCameraEditorChartEvents();
		previewChartEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		chartCameraEvents.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
		cameraEventListDirty = true;
		rebuildCameraEventList();
		previewChartEventCursor = 0;
		while (previewChartEventCursor < previewChartEvents.length && previewChartEvents[previewChartEventCursor].time <= songPos)
			previewChartEventCursor++;
	}

	function undo()
	{
		if (mode != None)
		{
			status("ปล่อยเมาส์ก่อนแล้วค่อย Undo");
			return;
		}
		if (history.length == 0)
		{
			status("ไม่มีอะไรให้ Undo");
			return;
		}
		var c = history.pop();
		c.undo();
		redoStack.push(c);
		afterHistory(c);
		status("Undo");
	}

	function redo()
	{
		if (mode != None)
		{
			status("ปล่อยเมาส์ก่อนแล้วค่อย Redo");
			return;
		}
		if (redoStack.length == 0)
		{
			status("ไม่มีอะไรให้ Redo");
			return;
		}
		var c = redoStack.pop();
		c.run();
		history.push(c);
		afterHistory(c);
		status("Redo");
	}

	// =====================================================================
	//  Save / Load / Navigation
	// =====================================================================
	/** ปรับ path ให้ตรงกับระบบ mod ของคุณ (เช่น Paths.mods(...)) */
	public function getSavePath():String
		return Paths.modFolders('songs/$songName/camera_events.json');

	/** Ctrl+S: save all chart + camera events into data/<song>/events.json after confirming overwrites. */
	function save():Void
		requestDataSave(true);

	/** Save built-in camera events (including Add Camera Zoom) to data/<song>/events.json. */
	function saveCameraOnly():Void
		requestDataSave(false);

	function requestDataSave(saveAll:Bool):Void
	{
		#if sys
		if (songName == null || songName.length == 0 || PlayState.SONG == null)
		{
			status('กรุณาเปิด Song Chart ก่อนบันทึก');
			return;
		}
		var path = getDataEventsPath();
		var action:Void->Void = function()
		{
			if (saveAll) saveAllEventsToDataNow();
			else saveCameraEventsToDataNow();
		};
		if (FileSystem.exists(path) && !FileSystem.isDirectory(path))
			showSaveConfirmation(path, action);
		else
			action();
		#else
		status('การเซฟลง data ใช้ได้เฉพาะ target ที่เป็น sys');
		#end
	}

	function saveCameraEventsToDataNow():Void
	{
		var oldMode = saveOtherEvents;
		saveOtherEvents = false;
		try
		{
			normalizeDuplicateEditorKeys();
			sortEvents();
			var dataPath = writeDataEvents();
			if (dataPath != null)
				status('Saved camera events (including Add Camera Zoom) -> ' + dataPath);
			else if (dataExportError != null) status('บันทึก Camera Events ไม่สำเร็จ: ' + dataExportError);
			else status('ไม่มีอีเวนต์กล้องให้บันทึก');
		}
		catch (e:Dynamic) status('บันทึก Camera Events ไม่สำเร็จ: ' + Std.string(e));
		saveOtherEvents = oldMode;
	}

	function saveAllEventsToDataNow():Void
	{
		var oldMode = saveOtherEvents;
		saveOtherEvents = true;
		try
		{
			normalizeDuplicateEditorKeys();
			sortEvents();
			var dataPath = writeDataEvents();
			if (dataPath != null)
				status('Saved ALL events (camera + Add Camera Zoom + other chart events) -> ' + dataPath);
			else if (dataExportError != null) status('บันทึก Events ไม่สำเร็จ: ' + dataExportError);
			else status('ไม่มี event ให้บันทึก');
		}
		catch (e:Dynamic) status('บันทึก Events ไม่สำเร็จ: ' + Std.string(e));
		saveOtherEvents = oldMode;
	}

	/** PlayTest only: install the editor's current camera keys into in-memory SONG.events. No files are written. */
	function doSave(writeData:Bool, cameraOnly:Bool = true):Void
	{
		var oldMode = saveOtherEvents;
		saveOtherEvents = !cameraOnly;
		try
		{
			normalizeDuplicateEditorKeys();
			sortEvents();
			if (PlayState.SONG != null)
			{
				var merged = buildDataEvents();
				Reflect.setField(PlayState.SONG, 'events', merged);
				if (writeData) {
					var p = writeDataEvents();
					if (p != null) status('Saved events -> ' + p);
				} else status('Camera events prepared for Play Test (no files written)');
			}
		}
		catch (e:Dynamic) status('เตรียมอีเวนต์สำหรับ Play Test ไม่สำเร็จ: ' + Std.string(e));
		saveOtherEvents = oldMode;
	}

	function showSaveConfirmation(path:String, onYes:Void->Void):Void
	{
		saveConfirmOpen = true;
		saveConfirmPath = path;
		saveConfirmYesAction = onYes;
		activeMenu = null;
		saveConfirmX = (FlxG.width - 560) * 0.5;
		saveConfirmY = (FlxG.height - 190) * 0.5;
		if (saveConfirmDim == null)
		{
			saveConfirmDim = new FlxSprite(0, 32).makeGraphic(FlxG.width, FlxG.height, 0xB0000000);
			saveConfirmPanel = new FlxSprite().makeGraphic(560, 190, 0xFF202A38);
			saveConfirmTitle = new FlxText(0, 0, 520, 'Overwrite existing data event file?', 16);
			saveConfirmBody = new FlxText(0, 0, 520, '', 11);
			saveConfirmYes = new FlxText(0, 0, 130, 'YES, OVERWRITE', 12);
			saveConfirmNo = new FlxText(0, 0, 100, 'CANCEL', 12);
			saveConfirmTitle.color = FlxColor.WHITE;
			saveConfirmBody.color = 0xFFD8E0EA;
			saveConfirmYes.color = 0xFF8FE3A0;
			saveConfirmNo.color = 0xFFFFA0A0;
			for (widget in [saveConfirmDim, saveConfirmPanel]) widget.cameras = [editorUICamera];
			for (widget in [saveConfirmTitle, saveConfirmBody, saveConfirmYes, saveConfirmNo]) widget.cameras = [editorUICamera];
			add(saveConfirmDim); add(saveConfirmPanel); add(saveConfirmTitle); add(saveConfirmBody); add(saveConfirmYes); add(saveConfirmNo);
		}
		saveConfirmDim.visible = true;
		saveConfirmPanel.visible = true;
		saveConfirmTitle.visible = true;
		saveConfirmBody.visible = true;
		saveConfirmYes.visible = true;
		saveConfirmNo.visible = true;
		saveConfirmDim.setPosition(0, 0);
		saveConfirmPanel.setPosition(saveConfirmX, saveConfirmY);
		saveConfirmTitle.setPosition(saveConfirmX + 20, saveConfirmY + 16);
		saveConfirmBody.text = 'This file already exists. Replace it only if you want to overwrite the events currently stored there.\n' + path;
		saveConfirmBody.setPosition(saveConfirmX + 20, saveConfirmY + 50);
		saveConfirmYes.setPosition(saveConfirmX + 290, saveConfirmY + 150);
		saveConfirmNo.setPosition(saveConfirmX + 440, saveConfirmY + 150);
		bringSaveConfirmToFront();
	}

	/** Re-insert the dialog widgets at the very end of the member list so they draw above the canvas (VCam frame etc.). */
	function bringSaveConfirmToFront():Void
	{
		for (w in [saveConfirmDim, saveConfirmPanel, saveConfirmTitle, saveConfirmBody, saveConfirmYes, saveConfirmNo])
		{
			if (w == null) continue;
			remove(w, true);
			insert(members.length, w);
		}
	}

	function closeSaveConfirmation():Void
	{
		saveConfirmOpen = false;
		saveConfirmYesAction = null;
		for (widget in [saveConfirmDim, saveConfirmPanel, saveConfirmTitle, saveConfirmBody, saveConfirmYes, saveConfirmNo])
			if (widget != null) widget.visible = false;
	}

	function confirmSaveOverwrite():Void
	{
		var action = saveConfirmYesAction;
		closeSaveConfirmation();
		if (action != null) action();
	}

	#if sys
	function ensureSaveDirectory(dir:String):Void
	{
		if (dir == null || dir.length == 0 || FileSystem.exists(dir)) return;
		var parent = haxe.io.Path.directory(dir);
		if (parent != dir && parent.length > 0 && !FileSystem.exists(parent)) ensureSaveDirectory(parent);
		if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
	}
	#end

	/** เรียกทุกเฟรมจาก update(): นับเวลา แล้ว autosave เมื่อครบรอบ (ไม่เขียนไฟล์ระหว่างเล่น กันกระตุก) */
	function autosaveTick(elapsed:Float):Void
	{
		#if sys
		if (lastAutosaveJson == null)
		{
			// เฟรมแรกหลังเปิด editor: จดสถานะตั้งต้นไว้เทียบ (ยังไม่เขียนไฟล์ เพราะยังไม่มีอะไรเปลี่ยน)
			try lastAutosaveJson = backupJson() catch (_:Dynamic) {}
			return;
		}
		if (playing) return;
		autosaveTimer += elapsed;
		if (autosaveTimer < AUTOSAVE_INTERVAL) return;
		autosaveTimer = 0;
		autosaveBackup(true);
		#end
	}

	/** ชื่อไฟล์ backup ที่ไม่ซ้ำ: <prefix>_<วันเวลา>_<เลขลำดับ>.json (อยู่ในวินาทีเดียวกันก็ไม่ทับกัน) */
	function uniqueBackupPath(dir:String, prefix:String):String
	{
		var stamp = DateTools.format(Date.now(), '%Y%m%d_%H%M%S');
		var path:String;
		do
		{
			backupSerial++;
			path = dir + '/' + prefix + '_' + stamp + '_' + (backupSerial < 10 ? '0' : '') + backupSerial + '.json';
		}
		while (FileSystem.exists(path));
		return path;
	}

	function backupDirForSong():String
		return BACKUP_DIR + '/' + Paths.formatToSongPath(songName);

	/** สำเนาไฟล์เดิมเข้า backup ก่อนถูกเขียนทับ (ข้ามถ้าไม่มีไฟล์) */
	function backupExistingFile(path:String, prefix:String):Void
	{
		try
		{
			if (path == null || !FileSystem.exists(path)) return;
			var dir = backupDirForSong();
			ensureSaveDirectory(dir);
			File.copy(path, uniqueBackupPath(dir, prefix));
			pruneBackups(dir, prefix + '_');
		}
		catch (_:Dynamic) {}
	}

	/** event ทุกตัวใน Chart (รวม Add Camera Zoom, Set Camzoom ฯลฯ และ event อื่นทั้งหมด) สำหรับ backup: ไม่ขึ้นกับโหมด Save */
	function allChartEventsForBackup():Array<Dynamic>
	{
		var out:Array<Dynamic> = [];
		if (PlayState.SONG == null || PlayState.SONG.events == null) return out;
		for (raw in PlayState.SONG.events)
		{
			if (raw == null || !Std.isOfType(raw, Array)) continue;
			var row:Array<Dynamic> = cast raw;
			if (row.length < 2 || row[1] == null || !Std.isOfType(row[1], Array)) continue;
			var subs:Array<Dynamic> = cast row[1];
			var copy:Array<Dynamic> = [];
			for (sub in subs)
				if (sub != null && Std.isOfType(sub, Array)) copy.push((cast sub : Array<Dynamic>).copy());
			if (copy.length > 0) out.push([row[0], copy]);
		}
		return out;
	}

	/** ข้อมูลสำหรับ backup/เทียบการเปลี่ยนแปลง: กล้องของ editor + event ของ Chart ทั้งหมด (นับ Add Camera Zoom และ event อื่นด้วย) */
	function backupJson():String
	{
		var data:Dynamic = {song: songName, stage: stageName, layers: {focus: focusLayers, zoom: zoomLayers, tilt: tiltLayers}, events: events};
		Reflect.setField(data, 'chartEvents', allChartEventsForBackup());
		return Json.stringify(data, null, "  ");
	}

	/** เขียนสำเนา backup ลง BACKUP_DIR/<เพลง>/<เพลง>_<วันเวลา>_<ลำดับ>.json (ข้ามถ้าไม่มีอะไรเปลี่ยนจากครั้งก่อน)
	 *  นอกจากนี้สำรอง events.json ใน data ที่มีอยู่ตอนนี้ด้วย (ถ้าเปลี่ยนไปจากที่สำรองไว้) */
	function autosaveBackup(announce:Bool):Void
	{
		#if sys
		try
		{
			if (songName == null || songName.length == 0) return;
			var json = backupJson();
			backupDataEventsFile();
			if (json == lastAutosaveJson) return;
			var slug = Paths.formatToSongPath(songName);
			var dir = BACKUP_DIR + '/' + slug;
			ensureSaveDirectory(dir);
			var path = uniqueBackupPath(dir, slug);
			File.saveContent(path, json);
			lastAutosaveJson = json;
			pruneBackups(dir, slug + '_');
			if (announce) status('Autosave -> $path');
		}
		catch (e:Dynamic) status('Autosave ไม่สำเร็จ: ' + Std.string(e));
		#end
	}

	#if sys
	/** สำรอง data/<เพลง>/events.json ที่มีอยู่จริงตอนนี้ (ไม่ทับ backup ตัวเก่า; ข้ามถ้าเนื้อเหมือนที่เคยสำรองแล้ว) */
	function backupDataEventsFile():Void
	{
		try
		{
			var path = getDataEventsPath();
			if (!FileSystem.exists(path)) return;
			var text = File.getContent(path);
			if (text == lastDataEventsBackupText) return;
			var dir = backupDirForSong();
			ensureSaveDirectory(dir);
			File.saveContent(uniqueBackupPath(dir, 'events_before_export'), text);
			lastDataEventsBackupText = text;
			pruneBackups(dir, 'events_before_export_');
		}
		catch (_:Dynamic) {}
	}

	/** เก็บ backup แค่ AUTOSAVE_KEEP ไฟล์ล่าสุดของเพลงนี้ (แยกตาม prefix) ลบตัวเก่าสุดทิ้ง */
	function pruneBackups(dir:String, prefix:String):Void
	{
		var files:Array<String> = [];
		for (f in FileSystem.readDirectory(dir))
			if (camStartsWith(f, prefix) && camEndsWith(f, '.json')) files.push(f);
		files.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0)); // ชื่อมีวันเวลา เรียงตามตัวอักษร = เรียงตามเวลา
		while (files.length > AUTOSAVE_KEEP)
		{
			var oldest = files.shift();
			try FileSystem.deleteFile(dir + '/' + oldest) catch (_:Dynamic) {}
		}
	}
	#end

	/** Return the resolved, time-sorted camera timeline currently visible in the editor. */
	function exportableCameraEvents():Array<CamEvent>
	{
		rebuildCameraEventCache();
		var out:Array<CamEvent> = [];
		for (e in sortedCameraEvents)
			if (e != null && (e.track == 'focus' || e.track == 'general' || e.track == 'zoom' || e.track == 'tilt' || e.track == 'kick'))
				out.push(copyEv(e));
		out.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		return out;
	}

	inline function exportNumber(v:Float):String
		return Math.isNaN(v) ? '0' : Std.string(Math.round(v * 10000) / 10000);

	function exportQuoted(v:String):String
	{
		if (v == null) v = '';
		return '"' + v.split('\\').join('\\\\').split('"').join('\\"').split('\r').join('').split('\n').join('\\n') + '"';
	}

	function exportWithSaveDialog(contents:String, extension:String, suffix:String = '-camera-events'):Void
	{
		var safeName = songName == null || songName.length == 0 ? 'camera' : Paths.formatToSongPath(songName);
		var file = new FileReference();
		try
		{
			file.save(contents, safeName + suffix + '.' + extension);
			status('กำลังส่งออก Camera Events เป็น .' + extension + ' ...');
		}
		catch (e:Dynamic) status('ส่งออก .' + extension + ' ไม่สำเร็จ: ' + Std.string(e));
	}

	function exportPsych063Lua():Void
		exportPsychLua('0.6.3', '-camera-events-psych-0.6.3');

	function exportPsych104Lua():Void
		exportPsychLua('1.0.4+', '-camera-events-psych-1.0.4');

	/** Export a self-contained camera script. Timeline triggers are editable curStep values. */
	function exportPsychLua(targetVersion:String, fileSuffix:String):Void
	{
		// Psych exports intentionally omit Add Camera Zoom (the editor's "kick" track).
		// Keep this filter local so other targets can handle that event independently.
		var list:Array<CamEvent> = [];
		for (e in exportableCameraEvents())
			if (e.track != 'kick') list.push(e);
		var b = new StringBuf();
		b.add('-- Generated by Camera Editor for Psych Engine ' + targetVersion + '.\n');
		b.add('-- This is a standalone camera timeline; it does not require chart camera events or helper Lua files.\n');
		b.add('-- Add Camera Zoom events are intentionally omitted.\n');
		b.add('-- Place it in the song Lua folder recognized by this build, or merge it into that song script.\n');
		b.add('-- Triggers use curStep; edit the step fields below to move keys. Durations remain seconds.\n');
		b.add('-- Merge with an existing script rather than overwriting other song logic.\n\n');
		b.add('local cameraEvents = {\n');
		for (e in list)
		{
			var eventStep = Conductor.getStepRounded(e.time);
			b.add('  {step=' + exportNumber(eventStep) + ', track=' + exportQuoted(e.track) + ', x=' + exportNumber(e.x) + ', y=' + exportNumber(e.y)
				+ ', zoom=' + exportNumber(e.zoom) + ', duration=' + exportNumber(e.duration / 1000) + ', ease=' + exportQuoted(e.ease)
				+ ', target=' + Std.string(e.target) + ', angle=' + exportNumber(angleOf(e)) + ', autoRelease=' + (e.autoRelease == true ? 'true' : 'false') + '},\n');
		}
		b.add('}\nlocal cameraEventIndex = 1\nlocal cameraLastStep = -1\nlocal cameraAutoReleaseAt = -1\nlocal cameraZoomTarget = nil\nlocal cameraZoomSavedEnabled = nil\nlocal cameraZoomEndAt = -1\nlocal cameraZoomEase = "linear"\n\n');
		b.add('local function cameraCancel(tag)\n  pcall(cancelTween, tag)\nend\n\n');
		b.add('local function cameraFinishZoom()\n  if cameraZoomTarget == nil then return end\n  cameraCancel("cameraEditorZoom")\n  setProperty("camGame.zoom", cameraZoomTarget)\n  setProperty("defaultCamZoom", cameraZoomTarget)\n  if cameraZoomSavedEnabled ~= nil then setProperty("camZooming", cameraZoomSavedEnabled) end\n  cameraZoomSavedEnabled = nil; cameraZoomTarget = nil; cameraZoomEndAt = -1\nend\n\n');
		b.add('local function cameraGetFocus(e)\n');
		b.add('  local x, y = e.x, e.y\n  if e.target == 0 then\n');
		b.add("    x = getMidpointX('boyfriend') - getProperty('boyfriend.cameraPosition[0]') + getProperty('boyfriendCameraOffset[0]') - 100 + e.x\n");
		b.add("    y = getMidpointY('boyfriend') + getProperty('boyfriend.cameraPosition[1]') + getProperty('boyfriendCameraOffset[1]') - 100 + e.y\n  elseif e.target == 1 then\n");
		b.add("    x = getMidpointX('dad') + getProperty('dad.cameraPosition[0]') + getProperty('opponentCameraOffset[0]') + 150 + e.x\n");
		b.add("    y = getMidpointY('dad') + getProperty('dad.cameraPosition[1]') + getProperty('opponentCameraOffset[1]') - 100 + e.y\n  elseif e.target == 2 then\n");
		b.add("    x = getMidpointX('gf') + getProperty('gf.cameraPosition[0]') + getProperty('girlfriendCameraOffset[0]') + e.x\n");
		b.add("    y = getMidpointY('gf') + getProperty('gf.cameraPosition[1]') + getProperty('girlfriendCameraOffset[1]') + e.y\n  end\n  return x, y\nend\n\n");
			// Runtime durations are measured from the moment the curStep trigger fires, so hand-editing
			// a step never leaves a stale millisecond timestamp in the exported script.
			b.add('local function applyCameraEvent(e)\n  if e.track == "focus" or e.track == "general" then\n    if e.target == -2 then\n      cameraAutoReleaseAt = -1\n      cameraCancel("cameraEditorMoveX"); cameraCancel("cameraEditorMoveY")\n      setProperty("isCameraOnForcedPos", false)\n      pcall(callMethod, "moveCameraSection", {curSection})\n      return\n    end\n    cameraAutoReleaseAt = e.autoRelease and (getSongPosition() + e.duration * 1000) or -1\n    local x, y = cameraGetFocus(e)\n    setProperty("isCameraOnForcedPos", true)\n    cameraCancel("cameraEditorMoveX"); cameraCancel("cameraEditorMoveY")\n    if e.duration <= 0 then\n      setProperty("camFollow.x", x); setProperty("camFollow.y", y)\n      pcall(setProperty, "camFollowPos.x", x); pcall(setProperty, "camFollowPos.y", y)\n      setProperty("camGame.scroll.x", x - screenWidth * 0.5)\n      setProperty("camGame.scroll.y", y - screenHeight * 0.5)\n      pcall(callMethod, "camGame.snapToTarget", {""})\n    else\n      doTweenX("cameraEditorMoveX", "camFollow", x, e.duration, e.ease)\n      doTweenY("cameraEditorMoveY", "camFollow", y, e.duration, e.ease)\n    end\n  elseif e.track == "zoom" then\n    cameraCancel("cameraEditorZoom")\n    if cameraZoomSavedEnabled == nil then cameraZoomSavedEnabled = getProperty("camZooming") end\n    cameraZoomTarget = e.zoom\n    cameraZoomEndAt = getSongPosition() + e.duration * 1000\n    cameraZoomEase = e.ease\n    setProperty("defaultCamZoom", e.zoom)\n    if e.duration <= 0 then\n      cameraFinishZoom()\n    else\n      setProperty("camZooming", false)\n      doTweenZoom("cameraEditorZoom", "camGame", e.zoom, e.duration, e.ease)\n    end\n  elseif e.track == "tilt" then\n    -- Apply angle directly as a fallback; the carrier also cooperates with camMovement.lua when present.\n    cameraCancel("cameraEditorTilt"); cameraCancel("cameraEditorTiltCarrier")\n    if e.duration <= 0 then\n      setProperty("camGame.angle", e.angle)\n      pcall(setProperty, "dummyCamEvent.angle", e.angle)\n    else\n      doTweenAngle("cameraEditorTilt", "camGame", e.angle, e.duration, e.ease)\n      pcall(doTweenAngle, "cameraEditorTiltCarrier", "dummyCamEvent", e.angle, e.duration, e.ease)\n    end\n  end\nend\n\n');
			b.add('local function cameraDispatchThroughStep(step)\n  while cameraEventIndex <= #cameraEvents and cameraEvents[cameraEventIndex].step <= step do\n    applyCameraEvent(cameraEvents[cameraEventIndex])\n    cameraEventIndex = cameraEventIndex + 1\n  end\nend\n\nfunction onSongStart()\n  cameraCancel("cameraEditorZoom")\n  if cameraZoomSavedEnabled ~= nil then setProperty("camZooming", cameraZoomSavedEnabled) end\n  cameraZoomSavedEnabled = nil; cameraZoomTarget = nil; cameraZoomEndAt = -1\n  cameraEventIndex = 1; cameraLastStep = -1; cameraAutoReleaseAt = -1\nend\n\nfunction onUpdatePost(elapsed)\n  local step = curStep or 0\n  local songPos = getSongPosition()\n  if cameraLastStep >= 0 and step < cameraLastStep then\n    cameraEventIndex = 1\n    while cameraEventIndex <= #cameraEvents and cameraEvents[cameraEventIndex].step < step do cameraEventIndex = cameraEventIndex + 1 end\n  end\n  cameraDispatchThroughStep(step)\n  if cameraAutoReleaseAt >= 0 and songPos >= cameraAutoReleaseAt then\n    cameraAutoReleaseAt = -1\n    cameraCancel("cameraEditorMoveX"); cameraCancel("cameraEditorMoveY")\n    setProperty("isCameraOnForcedPos", false)\n    pcall(callMethod, "moveCameraSection", {curSection})\n  end\n  if cameraZoomTarget ~= nil and cameraZoomEndAt >= 0 and songPos >= cameraZoomEndAt then cameraFinishZoom() end\n  cameraLastStep = step\nend\n');
		exportWithSaveDialog(b.toString(), 'lua', fileSuffix);
	}

	function vSliceEaseParts(ease:String):Array<String>
	{
		if (ease == null || ease.length == 0) return ['linear', ''];
		var easeLength = ease.length;
		if (easeLength >= 5 && ease.substr(easeLength - 5, 5) == 'InOut') return [ease.substr(0, easeLength - 5), 'InOut'];
		if (easeLength >= 2 && ease.substr(easeLength - 2, 2) == 'In') return [ease.substr(0, easeLength - 2), 'In'];
		if (easeLength >= 3 && ease.substr(easeLength - 3, 3) == 'Out') return [ease.substr(0, easeLength - 3), 'Out'];
		return [ease, ''];
	}

	function vSliceSectionFocusAt(time:Float):Int
	{
		if (PlayState.SONG == null || PlayState.SONG.notes == null) return 1;
		var sectionIndex = previewSectionAt(time);
		var sections:Array<Dynamic> = cast PlayState.SONG.notes;
		if (sectionIndex < 0 || sectionIndex >= sections.length || sections[sectionIndex] == null) return 1;
		return Reflect.field(sections[sectionIndex], 'mustHitSection') == true ? 0 : 1;
	}

	/** Export the native V-Slice song-event JSON shape. Stock V-Slice has no native tilt or Add Camera Zoom event. */
	function exportVSliceJson():Void
	{
		var list = exportableCameraEvents();
		var out:Array<Dynamic> = [];
		var unsupported = 0;
		function addFocus(time:Float, target:Int, x:Float, y:Float, duration:Float, ease:String):Void
		{
			var stepMs = Math.max(1, Conductor.getCrotchetAtTime(time) / 4);
			var easeParts = vSliceEaseParts(ease);
			var useEase = duration <= 0 ? 'INSTANT' : easeParts[0];
			var useDir = duration <= 0 ? '' : easeParts[1];
			out.push({t: time, e: 'FocusCamera', v: {char: target, x: x, y: y, duration: duration <= 0 ? 0 : duration / stepMs, ease: useEase, easeDir: useDir}});
		}
		for (e in list)
		{
			var stepMs = Math.max(1, Conductor.getCrotchetAtTime(e.time) / 4);
			var durationSteps = Math.max(0, e.duration / stepMs);
			switch (e.track)
			{
				case 'general':
					addFocus(e.time, e.target >= 0 && e.target <= 2 ? e.target : -1, e.x, e.y, e.duration, e.ease);
				case 'focus':
					var target:Int = e.target == -2 ? vSliceSectionFocusAt(e.time) : e.target;
					var x = e.x;
					var y = e.y;
					if (target == -1 && e.target != -2)
					{
						var pos = resolveXY(e);
						x = pos[0]; y = pos[1];
					}
					addFocus(e.time, target, x, y, e.duration, e.ease);
					if (e.autoRelease == true && e.duration > 0)
						addFocus(e.time + e.duration, vSliceSectionFocusAt(e.time + e.duration), 0, 0, 0, 'INSTANT');
				case 'zoom':
					var easeParts = vSliceEaseParts(e.ease);
					out.push({t: e.time, e: 'ZoomCamera', v: {zoom: e.zoom, duration: durationSteps, ease: e.duration <= 0 ? 'INSTANT' : easeParts[0], easeDir: e.duration <= 0 ? '' : easeParts[1], mode: 'direct'}});
				case 'kick' | 'tilt':
					unsupported++;
				default:
					unsupported++;
			}
		}
		out.sort((a, b) -> a.t < b.t ? -1 : (a.t > b.t ? 1 : 0));
		var payload:Dynamic = {events: out};
		exportWithSaveDialog(Json.stringify(payload, null, '\t'), 'json', '-camera-events-vslice');
		status('V-Slice event fragment exported (' + out.length + ' native events; merge its events array into the song chart)' + (unsupported > 0 ? '; ' + unsupported + ' tilt/Add Camera Zoom keys omitted because stock V-Slice has no matching event' : ''));
	}

	/** Export a self-contained HScript .hx gameplay script for Codename Engine. */
	function exportCodenameHx():Void
	{
		var list = exportableCameraEvents();
		var b = new StringBuf();
		b.add('/* Auto-generated camera timeline for Codename Engine.\n');
		b.add(' * Put the downloaded file in songs/<song>/scripts/ (the exported filename may be kept).\n');
		b.add(' * Positions for character-target keys are resolved from the current stage in Camera Editor.\n */\n');
		b.add('import flixel.FlxG;\nimport flixel.tweens.FlxTween;\nimport flixel.tweens.FlxEase;\nimport funkin.backend.system.Conductor;\n\n');
		b.add('var cameraEvents:Array<Dynamic> = [\n');
		for (e in list)
		{
			var outX = (e.track == 'focus' || e.track == 'general') && e.target >= 0 ? resolveX(e) : e.x;
			var outY = (e.track == 'focus' || e.track == 'general') && e.target >= 0 ? resolveY(e) : e.y;
			b.add('  {time:' + exportNumber(e.time) + ', track:' + exportQuoted(e.track) + ', x:' + exportNumber(outX) + ', y:' + exportNumber(outY)
				+ ', zoom:' + exportNumber(e.zoom) + ', hudZoom:' + exportNumber(e.hudZoom == null ? e.zoom * 2 : e.hudZoom) + ', duration:' + exportNumber(e.duration) + ', ease:' + exportQuoted(e.ease)
				+ ', target:' + Std.string(e.target) + ', angle:' + exportNumber(angleOf(e)) + ', autoRelease:' + (e.autoRelease == true ? 'true' : 'false') + '},\n');
		}
		b.add('];\nvar cameraEventIndex:Int = 0;\nvar cameraLastSongPos:Float = -1;\nvar cameraSavedTarget:Int = 0;\nvar cameraHasSavedTarget:Bool = false;\nvar cameraAutoReleaseAt:Float = -1;\nvar cameraAngleTween:FlxTween = null;\nvar cameraZoomTween:FlxTween = null;\nvar cameraZoomWasEnabled:Bool = true;\nvar cameraZoomTweening:Bool = false;\nvar cameraZoomTarget:Float = 1;\nvar cameraZoomEndAt:Float = -1;\n\n');
		b.add('function cameraEase(name:String):Dynamic {\n  var ease = Reflect.getProperty(FlxEase, name);\n  return ease == null ? FlxEase.quadInOut : ease;\n}\n\n');
		b.add('function cameraApply(e:Dynamic, songPos:Float):Void {\n  switch (e.track) {\n    case "focus" | "general":\n      if (e.target == -2) {\n        cameraAutoReleaseAt = -1;\n        if (cameraHasSavedTarget) curCameraTarget = cameraSavedTarget;\n        cameraHasSavedTarget = false;\n        FlxG.camera.followEnabled = true;\n        moveCamera();\n        return;\n      }\n      cameraAutoReleaseAt = e.autoRelease ? (e.time + Math.max(0, e.duration)) : -1;\n      if (curCameraTarget != -1) { cameraSavedTarget = curCameraTarget; cameraHasSavedTarget = true; }\n      curCameraTarget = -1;\n      FlxTween.cancelTweensOf(camFollow, ["x", "y"]);\n      if (e.duration <= 0) {\n        camFollow.setPosition(e.x, e.y);\n        FlxG.camera.scroll.set(e.x - FlxG.camera.width * 0.5, e.y - FlxG.camera.height * 0.5);\n      } else {\n        FlxTween.tween(camFollow, {x:e.x, y:e.y}, e.duration / 1000, {ease:cameraEase(e.ease)});\n      }\n    case "zoom":\n      if (!cameraZoomTweening) cameraZoomWasEnabled = camZooming;\n      if (cameraZoomTween != null) { cameraZoomTween.cancel(); cameraZoomTween = null; }\n      defaultCamZoom = e.zoom;\n      cameraZoomTarget = e.zoom;\n      cameraZoomEndAt = e.time + Math.max(0, e.duration);\n      var zoomRemain:Float = Math.max(0, (cameraZoomEndAt - songPos) / 1000);\n      if (e.duration <= 0 || zoomRemain <= 0) {\n        FlxG.camera.zoom = e.zoom;\n        camZooming = cameraZoomWasEnabled;\n        cameraZoomTweening = false;\n        cameraZoomEndAt = -1;\n      } else {\n        cameraZoomTweening = true;\n        camZooming = false;\n        cameraZoomTween = FlxTween.tween(FlxG.camera, {zoom:e.zoom}, zoomRemain, {ease:cameraEase(e.ease)});\n      }\n    case "tilt":\n      if (cameraAngleTween != null) { cameraAngleTween.cancel(); cameraAngleTween = null; }\n      if (e.duration <= 0) FlxG.camera.angle = e.angle;\n      else {\n        var startAngle:Float = FlxG.camera.angle;\n        cameraAngleTween = FlxTween.num(startAngle, e.angle, e.duration / 1000, {ease:cameraEase(e.ease)}, function(value:Float) { FlxG.camera.angle = value; });\n      }\n    case "kick":\n      FlxG.camera.zoom += e.zoom;\n      if (camHUD != null) camHUD.zoom += e.hudZoom;\n  }\n}\n\n');
		b.add('function create():Void {\n  cameraEventIndex = 0;\n  cameraLastSongPos = -1;\n  cameraAutoReleaseAt = -1;\n  cameraSavedTarget = curCameraTarget;\n  cameraHasSavedTarget = false;\n  cameraZoomTweening = false;\n  cameraZoomTween = null;\n}\n\nfunction onSongStart():Void {\n  if (cameraZoomTween != null) { cameraZoomTween.cancel(); cameraZoomTween = null; }\n  if (cameraZoomTweening) camZooming = cameraZoomWasEnabled;\n  cameraZoomTweening = false;\n  cameraZoomEndAt = -1;\n  cameraEventIndex = 0;\n  cameraLastSongPos = -1;\n  cameraAutoReleaseAt = -1;\n}\n\nfunction postUpdate(elapsed:Float):Void {\n  var songPos:Float = Conductor.songPosition;\n  if (cameraLastSongPos >= 0 && songPos < cameraLastSongPos) {\n    cameraEventIndex = 0;\n    while (cameraEventIndex < cameraEvents.length && cameraEvents[cameraEventIndex].time < songPos) cameraEventIndex++;\n  }\n  while (cameraEventIndex < cameraEvents.length && cameraEvents[cameraEventIndex].time <= songPos) {\n    cameraApply(cameraEvents[cameraEventIndex], songPos);\n    cameraEventIndex++;\n  }\n  if (cameraAutoReleaseAt >= 0 && songPos >= cameraAutoReleaseAt) {\n    cameraAutoReleaseAt = -1;\n    if (cameraHasSavedTarget) curCameraTarget = cameraSavedTarget;\n    cameraHasSavedTarget = false;\n    FlxG.camera.followEnabled = true;\n    moveCamera();\n  }\n  if (cameraZoomTweening && cameraZoomEndAt >= 0 && songPos >= cameraZoomEndAt) {\n    if (cameraZoomTween != null) { cameraZoomTween.cancel(); cameraZoomTween = null; }\n    FlxG.camera.zoom = cameraZoomTarget;\n    defaultCamZoom = cameraZoomTarget;\n    camZooming = cameraZoomWasEnabled;\n    cameraZoomTweening = false; cameraZoomEndAt = -1;\n  }\n  cameraLastSongPos = songPos;\n}\n');
		exportWithSaveDialog(b.toString(), 'hx');
	}

	function saveAs():Void
	{
		var picker = new FileReference();
		var filename = (songName == null || songName.length == 0 ? 'camera' : Paths.formatToSongPath(songName)) + '-camera-events.json';
		picker.save(layeredJson(), filename);
		status('กำลังบันทึก Camera Events...');
	}

	/** Save a copy of the Song Chart with camera-only, non-camera-only, or all event rows. */
	function saveFilteredSongChart(keepCameraEvents:Bool):Void
	{
		if (PlayState.SONG == null)
		{
			status('ไม่มี Song Chart ให้บันทึก');
			return;
		}
		var oldMode = saveOtherEvents;
		var filtered:Array<Dynamic> = [];
		try
		{
			if (keepCameraEvents)
			{
				saveOtherEvents = false;
				filtered = buildDataEvents(); // editor camera + chart camera events, including Add Camera Zoom
			}
			else
				filtered = otherChartEventsForSave();
		}
		catch (e:Dynamic)
		{
			saveOtherEvents = oldMode;
			status('เตรียม Song Chart ไม่สำเร็จ: ' + Std.string(e));
			return;
		}
		saveOtherEvents = oldMode;
		var modeName = keepCameraEvents ? 'camera events only' : 'non-camera events only';
		var suffix = keepCameraEvents ? '-camera-events' : '-non-camera-events';
		saveSongChartEvents(filtered, modeName, suffix);
	}

	/** Combine all camera timeline keys and non-camera chart events into SONG.events, then save a full chart. */
	function saveAllSongChart():Void
	{
		if (PlayState.SONG == null)
		{
			status('ไม่มี Song Chart ให้บันทึก');
			return;
		}
		var oldMode = saveOtherEvents;
		var allEvents:Array<Dynamic> = [];
		try
		{
			saveOtherEvents = true;
			normalizeDuplicateEditorKeys();
			sortEvents();
			allEvents = buildDataEvents();
		}
		catch (e:Dynamic)
		{
			saveOtherEvents = oldMode;
			status('เตรียม Full Song Chart ไม่สำเร็จ: ' + Std.string(e));
			return;
		}
		saveOtherEvents = oldMode;
		saveSongChartEvents(allEvents, 'all events', '-all-events');
	}

	/** Write an event-filtered chart while restoring the in-memory chart after serialization. */
	function saveSongChartEvents(filtered:Array<Dynamic>, modeName:String, suffix:String):Void
	{
		var original:Dynamic = Reflect.field(PlayState.SONG, 'events');
		var chartData:String = null;
		try
		{
			Reflect.setField(PlayState.SONG, 'events', filtered);
			chartData = PsychJsonPrinter.print(PlayState.SONG, ['sectionNotes', 'events']);
		}
		catch (e:Dynamic)
			status('สร้าง Song Chart ไม่สำเร็จ: ' + Std.string(e));
		try Reflect.setField(PlayState.SONG, 'events', original) catch (_:Dynamic) {}
		if (chartData == null) return;
		#if sys
		if (Song.chartPath != null && Song.chartPath.length > 0)
		{
			try
			{
				backupExistingFile(Song.chartPath, 'chart_before_save');
				File.saveContent(Song.chartPath, chartData);
				status('Saved Song Chart (' + modeName + ') -> ' + Song.chartPath);
			}
			catch (e:Dynamic) status('บันทึก Song Chart ไม่สำเร็จ: ' + Std.string(e));
			return;
		}
		#end
		if (chartSavePicker != null) chartSavePicker.destroy();
		chartSavePicker = new FileDialogHandler();
		var fileName = Paths.formatToSongPath(PlayState.SONG.song) + suffix + '.json';
		chartSavePicker.save(fileName, chartData, function()
		{
			if (chartSavePicker != null)
			{
				Song.chartPath = chartSavePicker.path;
				status('Saved Song Chart (' + modeName + ') -> ' + Song.chartPath);
				chartSavePicker.destroy();
				chartSavePicker = null;
			}
		}, function()
		{
			if (chartSavePicker != null) chartSavePicker.destroy();
			chartSavePicker = null;
		}, function()
		{
			status('บันทึก Song Chart ไม่สำเร็จ');
			if (chartSavePicker != null) chartSavePicker.destroy();
			chartSavePicker = null;
		});
		status('เลือกตำแหน่งบันทึก Song Chart (' + modeName + ')');
	}

	function layeredJson():String
	{
		var data:Dynamic = {song: songName, stage: stageName, layers: {focus: focusLayers, zoom: zoomLayers, tilt: tiltLayers}, events: events};
		// โหมด Camera + Other Events: แนบ event อื่นนอกเหนือกล้องของ Chart (รูปแบบเดียวกับ events ใน Chart) ไปในไฟล์เดียวกัน
		if (saveOtherEvents) Reflect.setField(data, 'chartEvents', otherChartEventsForSave());
		return Json.stringify(data, null, "  ");
	}

	/** event ใน Chart ที่ไม่ใช่เรื่องกล้อง (Play Animation, Hey!, Change Character ฯลฯ) ในรูปแบบ events ของ Chart: [[เวลา, [[ชื่อ, value1, value2], ...]], ...] */
	static function isCameraChartEventName(name:String):Bool
	{
		if (name == null) return false;
		return CAMERA_CHART_EVENT_NAMES.contains(name.trim().toLowerCase());
	}

	/** Canonical component for camera-event aliases. Old script events and newer native events
	 *  that control the same camera component must not create two overlapping timeline keys. */
	static function cameraEventComponent(name:String):String
	{
		if (name == null) return '';
		switch (name.trim().toLowerCase())
		{
			case 'target camera' | 'focuscamera' | 'focus camera' | 'camera follow pos' | 'camera warp pos' | 'camera focus xy': return 'focus';
			case 'zoomcamera' | 'zoom camera' | 'set camzoom' | 'set camera zoom' | 'defaultcamzoom': return 'zoom';
			case 'rol cam' | 'roll camera': return 'tilt';
			case 'add camera zoom': return 'kick';
			case 'set camera bopping': return 'bopping';
			// Camera Control contains both focus and zoom values; don't collapse it as one component.
			default: return '';
		}
	}

	static function cameraTrackComponent(track:String):String
		return track == 'general' ? 'focus' : track;

	static function editorCameraEventPriority(name:String):Int
	{
		if (name == null) return 0;
		switch (name.trim().toLowerCase())
		{
			case 'camera follow pos' | 'camera warp pos' | 'camera focus xy' | 'set camzoom' | 'set camera zoom' | 'rol cam' | 'roll camera' | 'add camera zoom': return 3;
			case 'focuscamera' | 'focus camera' | 'zoomcamera' | 'zoom camera': return 2;
			case 'target camera' | 'defaultcamzoom': return 1;
			default: return 0;
		}
	}

	/** Convert the legacy aggregate event into the native focus/zoom pieces it represents. */
	static function editorCameraControlSubEvents(sub:Array<Dynamic>):Array<Array<Dynamic>>
	{
		var out:Array<Array<Dynamic>> = [];
		if (sub == null || sub.length < 2) return out;
		var coordinates = sub[1] == null ? [] : Std.string(sub[1]).split(',');
		if (coordinates.length >= 2)
		{
			var x = Std.parseFloat(coordinates[0].trim());
			var y = Std.parseFloat(coordinates[1].trim());
			if (!Math.isNaN(x) && !Math.isNaN(y)) out.push(['Camera Follow Pos', camRound(x, 2), camRound(y, 2)]);
		}
		var zoom = sub.length > 2 ? Std.parseFloat(Std.string(sub[2])) : Math.NaN;
		if (!Math.isNaN(zoom) && zoom > 0) out.push(['Set Camzoom', camRound(zoom, 4), '0']);
		return out;
	}

	static inline function sameCameraEventTime(a:Float, b:Float):Bool
		return !Math.isNaN(a) && !Math.isNaN(b) && Math.abs(a - b) < 1.0;

	function chartCameraLinkShadowedByEditor(link:ChartCameraLink):Bool
	{
		if (link == null || link.camera == null) return false;
		var component = cameraTrackComponent(link.camera.track);
		for (key in events)
			if (key != null && cameraTrackComponent(key.track) == component && sameCameraEventTime(key.time, link.camera.time))
				return true;
		return false;
	}

	/** Keep one chart-source key per component/time. Prefer the newer built-in event alias,
	 *  and otherwise keep the first source entry. A saved editor key takes precedence over all of them. */
	function chartCameraLinkIsDuplicate(link:ChartCameraLink):Bool
	{
		if (link == null || link.camera == null || link.source == null) return false;
		if (chartCameraLinkShadowedByEditor(link)) return true;
		var component = cameraTrackComponent(link.camera.track);
		var myPriority = editorCameraEventPriority(link.source.name);
		var myOrder = previewChartEvents.indexOf(link.source);
		for (other in chartCameraLinks)
		{
			if (other == link || other.camera == null || other.source == null) continue;
			if (cameraTrackComponent(other.camera.track) != component || !sameCameraEventTime(other.camera.time, link.camera.time)) continue;
			if (chartCameraLinkShadowedByEditor(other)) continue;
			var otherPriority = editorCameraEventPriority(other.source.name);
			var otherOrder = previewChartEvents.indexOf(other.source);
			if (otherPriority > myPriority || (otherPriority == myPriority && otherOrder >= 0 && myOrder >= 0 && otherOrder < myOrder))
				return true;
		}
		return false;
	}

	function chartCameraLinkVisible(link:ChartCameraLink):Bool
		return link != null && !chartCameraLinkIsDuplicate(link);

	function otherChartEventsForSave():Array<Dynamic>
	{
		var out:Array<Dynamic> = [];
		if (PlayState.SONG == null || PlayState.SONG.events == null) return out;
		for (raw in PlayState.SONG.events)
		{
			if (raw == null || !Std.isOfType(raw, Array)) continue;
			var row:Array<Dynamic> = cast raw;
			if (row.length < 2 || row[1] == null || !Std.isOfType(row[1], Array)) continue;
			var subs:Array<Dynamic> = cast row[1];
			var kept:Array<Dynamic> = [];
			for (sub in subs)
			{
				if (sub == null || !Std.isOfType(sub, Array)) continue;
				var item:Array<Dynamic> = cast sub;
				if (item.length < 1) continue;
				if (isCameraChartEventName(Std.string(item[0]))) continue;
				kept.push(item.copy());
			}
			if (kept.length > 0) out.push([row[0], kept]);
		}
		return out;
	}

	function toggleSaveOtherEvents():Void
	{
		saveOtherEvents = !saveOtherEvents;
		status('Save Events: ' + (saveOtherEvents ? 'All Song Events' : 'Camera Events Only'));
	}

	// =====================================================================
	//  Export เป็น event ใน data (PlayState อ่านเอง)
	// =====================================================================
	/** ไฟล์ events ของเพลงใน data: PlayState โหลด data/<เพลง>/events.json ต่อท้าย event ของ Chart ทุกครั้งที่เริ่มเพลง */
	function getDataEventsPath():String
	{
		var slug = Paths.formatToSongPath(songName);
		#if sys
		if (Song.chartPath != null && Song.chartPath.length > 0)
		{
			var normalized = Song.chartPath.split('\\').join('/');
			var lower = normalized.toLowerCase();
			var marker = '/songs/';
			var at = lower.lastIndexOf(marker);
			if (at >= 0) return normalized.substr(0, at) + '/data/' + slug + '/events.json';
			var dataMarker = '/data/' + slug + '/';
			var dataAt = lower.lastIndexOf(dataMarker);
			if (dataAt >= 0) return normalized.substr(0, dataAt) + dataMarker + 'events.json';
		}
		#end
		var dir = selectedChartDirectory();
		if (dir != null && dir.toLowerCase().indexOf('/data/') >= 0) return dir + '/events.json';
		return Paths.modFolders('data/' + slug + '/events.json');
	}

	static function camRound(v:Float, digits:Int):String
	{
		var m = Math.pow(10, digits);
		return Std.string(Math.round(v * m) / m);
	}

	/** แปลงคีย์กล้องของ editor (Focus / Zoom / General) เป็น event แบบเดียวกับใน Chart: [ชื่อ, value1, value2]
	 *  ใช้รูปแบบเดียวกับที่ editor เขียนกลับให้ event ของ Chart (FocusCamera.lua / ZoomCamera) ส่วนกรณี focus แบบปกติใช้ Camera Follow Pos และแบบ Warp ใช้ Camera Warp Pos */
	function cameraKeyToChartEvent(e:CamEvent):Array<Dynamic>
	{
		var charName = e.target == 0 ? 'bf' : (e.target == 1 ? 'dad' : (e.target == 2 ? 'gf' : ''));
		var stepMs = Math.max(1, Conductor.getCrotchetAtTime(e.time) / 4);
		switch (e.track)
		{
			case 'general':
				if (charName == '') return null;
				return ['FocusCamera', charName, ''];
			case 'focus':
				if (e.target == -2) return ['FocusCamera', '', '']; // release: คืนการติดตาม section
				var pos = resolveXY(e);
				if (e.target >= 0 && e.target <= 2)
				{
					var stepCount = e.duration <= 0 ? 0 : e.duration / stepMs;
					var focusTiming = stepCount <= 0 ? (e.autoRelease == true ? '0,linear' : '0') : camRound(stepCount, 3) + ',' + e.ease;
					focusTiming = timingWithAutoRelease(focusTiming, e.autoRelease == true);
					return ['FocusCamera', charName + ',' + camRound(e.x, 2) + ',' + camRound(e.y, 2), focusTiming];
				}
				// Custom world positions need a native duration-capable event; Camera Follow Pos has no duration field.
				if (e.duration > 0 || e.autoRelease == true)
				{
					var xyTiming = e.duration <= 0 ? '0,linear' : camRound(e.duration / stepMs, 3) + ',' + e.ease;
					xyTiming = timingWithAutoRelease(xyTiming, e.autoRelease == true);
					return ['Camera Focus XY', camRound(pos[0], 2) + ',' + camRound(pos[1], 2), xyTiming];
				}
				return ['Camera Warp Pos', camRound(pos[0], 2), camRound(pos[1], 2)];
			case 'zoom':
				// Native event handled by PlayState.triggerEvent; no ZoomCamera.lua dependency.
				return ['Set Camzoom', camRound(e.zoom, 4), e.duration <= 0 ? '0' : camRound(e.duration / 1000, 3)];
			case 'kick':
				return ['Add Camera Zoom', camRound(e.zoom, 4), camRound(e.hudZoom == null ? e.zoom * 2 : e.hudZoom, 4)];
			case 'tilt':
				// event Rol cam ในตัว PlayState: Value 1 = มุม, Value 2 = วินาที,Ease
				return ['Rol cam', camRound(angleOf(e), 2), camRound(e.duration / 1000, 3) + ',' + e.ease];
			default:
				return null;
		}
	}

	/** รวมคีย์กล้องของ editor (+ event อื่นนอกเหนือกล้องของ Chart ถ้าเปิดโหมด Camera + Other Events) เป็น events แบบใน data เรียงตามเวลา */
	function buildDataEvents():Array<Dynamic>
	{
		var rows:Array<Dynamic> = [];
		var noteOffset = ClientPrefs.data.noteOffset;
		var editorComponents:Map<String, Bool> = new Map<String, Bool>();
		function addSub(time:Float, sub:Array<Dynamic>, fromEditorKey:Bool = false):Void
		{
			if (sub == null || sub.length == 0 || Math.isNaN(time)) return;
			var rowTarget:Array<Dynamic> = null;
			for (row in rows)
			{
				var r:Array<Dynamic> = cast row;
				if (Math.abs(Std.parseFloat(Std.string(r[0])) - time) < 1.0)
				{
					rowTarget = r;
					break;
				}
			}
			if (rowTarget == null)
			{
				rowTarget = [time, []];
				rows.push(rowTarget);
			}
			var subs:Array<Dynamic> = cast rowTarget[1];
			var encoded = Json.stringify(sub);
			var newComponent = sub.length > 0 ? cameraEventComponent(Std.string(sub[0])) : '';
			var componentKey = newComponent.length > 0 ? Std.string(Math.round(time)) + '|' + newComponent : '';
			if (fromEditorKey && componentKey.length > 0) editorComponents.set(componentKey, true);
			for (i in 0...subs.length)
			{
				var oldSub:Dynamic = subs[i];
				if (oldSub == null || !Std.isOfType(oldSub, Array)) continue;
				var old:Array<Dynamic> = cast oldSub;
				if (Json.stringify(old) == encoded) return;
				if (old.length == 0 || newComponent.length == 0) continue;
				var oldComponent = cameraEventComponent(Std.string(old[0]));
				if (oldComponent != newComponent) continue;
				var oldTime = Std.parseFloat(Std.string(rowTarget[0]));
				if (!sameCameraEventTime(oldTime, time)) continue;
				// Editor keys win over every Chart/data alias at the same camera component + time.
				if (fromEditorKey)
					subs[i] = sub.copy();
				else if (editorComponents.exists(componentKey))
					return;
				else if (editorCameraEventPriority(Std.string(sub[0])) > editorCameraEventPriority(Std.string(old[0])))
					subs[i] = sub.copy();
				return;
			}
			subs.push(sub.copy());
		}

		// Custom editor keys are converted to native Chart events.
		for (e in events)
		{
			var sub = cameraKeyToChartEvent(e);
			if (sub != null) addSub(Math.max(0, e.time - noteOffset), sub, true);
		}

		// Import the event sources from the loaded chart AND the merged data/events.json.
		// Camera-only mode keeps normal events in the chart, while Add Camera Zoom and all known
		// camera events are explicitly exported to events.json. All mode exports every event.
		if (PlayState.SONG != null && PlayState.SONG.events != null)
			for (raw in PlayState.SONG.events)
			{
				if (raw == null || raw.length < 2 || raw[1] == null) continue;
				var time = Std.parseFloat(Std.string(raw[0]));
				if (Math.isNaN(time)) continue;
				var subs:Array<Dynamic> = cast raw[1];
				if (subs == null) continue;
				for (sub in subs)
				{
					if (sub == null || !Std.isOfType(sub, Array)) continue;
					var item:Array<Dynamic> = cast sub;
					if (item.length == 0) continue;
					var lowerEvent = Std.string(item[0]).trim().toLowerCase();
					var cameraEvent = isCameraChartEventName(lowerEvent);
					if (!(saveOtherEvents || cameraEvent)) continue;
					if (lowerEvent == 'camera control')
					{
						// It controls two independent components. Export each one only if an editor key
						// hasn't already replaced that component at the same timestamp.
						for (controlSub in editorCameraControlSubEvents(item)) addSub(time, controlSub);
						continue;
					}
					addSub(time, item);
				}
			}

		rows.sort((a, b) ->
		{
			var ta = Std.parseFloat(Std.string(a[0]));
			var tb = Std.parseFloat(Std.string(b[0]));
			ta < tb ? -1 : (ta > tb ? 1 : 0);
		});
		return rows;
	}

	/** Writes a filtered Chart copy: camera-only mode leaves regular events in chart JSON; All moves all events. */
	function writeChartEventsFiltered(cameraOnly:Bool):Bool
	{
		#if sys
		if (PlayState.SONG == null || Song.chartPath == null || Song.chartPath.length == 0) return false;
		var original:Dynamic = Reflect.field(PlayState.SONG, 'events');
		var success = false;
		try
		{
			var keptRows:Array<Dynamic> = [];
			if (cameraOnly && original != null && Std.isOfType(original, Array))
				for (raw in (cast original:Array<Dynamic>))
				{
					if (raw == null || !Std.isOfType(raw, Array)) continue;
					var row:Array<Dynamic> = cast raw;
					if (row.length < 2 || row[1] == null || !Std.isOfType(row[1], Array)) continue;
					var subs:Array<Dynamic> = cast row[1];
					var kept:Array<Dynamic> = [];
					for (sub in subs)
					{
						if (sub == null || !Std.isOfType(sub, Array)) continue;
						var item:Array<Dynamic> = cast sub;
						if (item.length == 0 || !isCameraChartEventName(Std.string(item[0]))) kept.push(item.copy());
					}
					if (kept.length > 0) keptRows.push([row[0], kept]);
				}
			Reflect.setField(PlayState.SONG, 'events', keptRows);
			backupExistingFile(Song.chartPath, 'chart_events_before_save');
			var chartText = PsychJsonPrinter.print(PlayState.SONG, ['sectionNotes', 'events']);
			File.saveContent(Song.chartPath, chartText);
			success = true;
		}
		catch (e:Dynamic)
			trace('Camera Editor: could not save filtered chart events: ' + Std.string(e));
		// Keep the editor's in-memory event data intact; only the on-disk Chart is filtered.
		try Reflect.setField(PlayState.SONG, 'events', original) catch (_:Dynamic) {}
		return success;
		#else
		return false;
		#end
	}

	/** เขียน data/<เพลง>/events.json (รูปแบบเดียวกับ Save Events ของ chart editor: {"song":{"events":[...]}}) คืน path ที่เขียน หรือ null */
	function writeDataEvents():String
	{
		dataExportError = null;
		#if sys
		try
		{
			if (songName == null || songName.length == 0) return null;
			var rows = buildDataEvents();
			var path = getDataEventsPath();
			if (rows.length == 0 && !FileSystem.exists(path)) return null; // ไม่มีอะไรให้เขียน และไม่มีไฟล์เดิมให้ล้าง
			ensureSaveDirectory(haxe.io.Path.directory(path));
			backupDataEventsFile(); // events.json เดิมถูกสำรองก่อนเขียนทับทุกครั้งที่เนื้อไฟล์เปลี่ยน (ไม่ใช่แค่ครั้งแรก)
			var payload:Dynamic = {song: {events: rows}};
			var text:String = null;
			try text = PsychJsonPrinter.print(payload, ['events']) catch (_:Dynamic) {}
			if (text == null) text = Json.stringify(payload, null, '\t');
			File.saveContent(path, text);
			return path;
		}
		catch (e:Dynamic) dataExportError = Std.string(e);
		#end
		return null;
	}

	function exportEventsToData():Void
	{
		var path = writeDataEvents();
		if (path != null) status('Export Events -> $path' + (saveOtherEvents ? ' (Camera + Other Events)' : ' (Camera Only)'));
		else if (dataExportError != null) status('Export Events ลง data ไม่สำเร็จ: ' + dataExportError);
		else status('ไม่มี event ให้ Export');
	}

	/** อ่านจำนวนเลเยอร์ที่บันทึกไว้ในไฟล์ (ไฟล์เก่าที่ไม่มีค่านี้ = 1 เลเยอร์ต่อ track) */
	function readLayerCounts(parsed:Dynamic):Void
	{
		focusLayers = 1;
		zoomLayers = 1;
		tiltLayers = 1;
		var layers:Dynamic = parsed == null ? null : Reflect.field(parsed, 'layers');
		if (layers == null) return;
		var f = Std.parseInt(Std.string(Reflect.field(layers, 'focus')));
		var z = Std.parseInt(Std.string(Reflect.field(layers, 'zoom')));
		var tl = Std.parseInt(Std.string(Reflect.field(layers, 'tilt')));
		if (f != null) focusLayers = Std.int(Math.max(1, Math.min(MAX_LAYERS_PER_TRACK, f)));
		if (z != null) zoomLayers = Std.int(Math.max(1, Math.min(MAX_LAYERS_PER_TRACK, z)));
		if (tl != null) tiltLayers = Std.int(Math.max(1, Math.min(MAX_LAYERS_PER_TRACK, tl)));
	}

	function newCameraEvents():Void
	{
		stopPreview();
		focusLayers = 1;
		zoomLayers = 1;
		tiltLayers = 1;
		events = [];
		cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
		cameraEventListDirty = true;
		syncCameraEvents();
		selected = null;
		history = [];
		redoStack = [];
		status('สร้าง Camera Events ใหม่แล้ว');
	}

	function stopPreview():Void
	{
		// A manual Stop/Rewind wins over a queued natural-end loop.
		previewEndPending = false;
		setPlayback(false);
		// setPlayback(false) can be a no-op when audio has just naturally stopped;
		// still freeze PlayState so the conductor/countdown cannot drift after rewinding.
		pauseCameraEditorPlayback();
		rewindPreviewAudio();
		seekTo(0);
		// Do not wait for update() to leave Seek mode: Lua/Event/camera cleanup must happen now,
		// otherwise a black fade or a tween from the previous play can remain stuck on screen.
		if (stageHost != null && generatedMusic)
			replayEventsTo(0);
		lastPreviewTime = 0;
	}

	function showHelp():Void
	{
		activeMenu = null;
		if (eventPickerOpen) closeChartEventPicker();
		helpOpen = true;
		layoutHelp();
	}

	/** Size the help window to its text (so nothing overflows) and center it in the whole editor window. */
	function layoutHelp():Void
	{
		if (helpText == null || helpPanel == null) return;
		setTextIfChanged(helpText, HELP_TEXT);
		var avail = FlxG.height - 32 - 16;
		var wanted = Std.int(Math.ceil(62 + helpText.height + 18 + 24 + 14));
		helpPanelH = Std.int(Math.max(220, Math.min(avail, wanted)));
		helpX = Math.round((FlxG.width - helpPanelW) * 0.5);
		helpY = Math.round(32 + (FlxG.height - 32 - helpPanelH) * 0.5);
		if (helpPanelBuiltH != helpPanelH)
		{
			helpPanelBuiltH = helpPanelH;
			helpPanel.makeGraphic(helpPanelW, helpPanelH, th(0xFF667383), true);
			tmpRect.setTo(2, 2, helpPanelW - 4, helpPanelH - 4);
			helpPanel.pixels.fillRect(tmpRect, th(0xFF252A32));
			tmpRect.setTo(2, 42, helpPanelW - 4, 1);
			helpPanel.pixels.fillRect(tmpRect, th(0xFF48515D));
			tmpRect.setTo(2, helpPanelH - 34, helpPanelW - 4, 1);
			helpPanel.pixels.fillRect(tmpRect, th(0xFF48515D));
			helpPanel.dirty = true;
		}
		helpPanel.setPosition(helpX, helpY);
		helpTitle.setPosition(helpX + 18, helpY + 13);
		helpText.setPosition(helpX + 20, helpY + 56);
		helpFooter.setPosition(helpX + 18, helpY + helpPanelH - 24);
	}

	/** Normalize layered keys left by older saves. A component can only own one editable key
	 *  at one timestamp: keep the last record (the most recently saved/editable version). */
	function normalizeDuplicateEditorKeys():Void
	{
		if (events == null) { events = []; return; }
		var unique:Array<CamEvent> = [];
		for (e in events)
		{
			if (e == null) continue;
			var duplicateIndex = -1;
			for (i in 0...unique.length)
			{
				var old = unique[i];
				if (old != null && cameraTrackComponent(old.track) == cameraTrackComponent(e.track) && sameCameraEventTime(old.time, e.time))
					duplicateIndex = i;
			}
			if (duplicateIndex >= 0) unique[duplicateIndex] = e;
			else unique.push(e);
		}
		events = unique;
	}

	function load()
	{
		// Native Chart + data/<song>/events.json now own camera events. Do not silently re-load
		// the obsolete songs/<song>/camera_events.json file: it can be stale and shadow newer keys.
		events = [];
		readLayerCounts(null);
	}


	/** Merge the separate data/<song>/events.json file into the selected chart before PlayState/editor reads events. */
	#if sys
	static function mergeSeparateDataEvents(chart:Dynamic, chartPath:String):Void
	{
		if (chart == null) return;
		var songValue:Dynamic = Reflect.field(chart, 'song');
		var songName = songValue == null ? '' : Std.string(songValue);
		if (songName.length == 0) return;
		var slug = Paths.formatToSongPath(songName);
		var candidates:Array<String> = [];
		function pushCandidate(path:String):Void
		{
			if (path != null && path.length > 0 && !candidates.contains(path)) candidates.push(path);
		}
		// Prefer data/<song>/events.json beside the selected chart's own mod. This is important
		// when the active mod differs from the mod containing the selected chart.
		if (chartPath != null && chartPath.length > 0)
		{
			var normalized = chartPath.split('\\').join('/');
			var lower = normalized.toLowerCase();
			var marker = '/songs/';
			var at = lower.lastIndexOf(marker);
			if (at >= 0)
			{
				var root = normalized.substr(0, at);
				pushCandidate(root + '/data/' + slug + '/events.json');
				pushCandidate(root + '/data/' + slug + '/event.json');
			}
			var dataMarker = '/data/' + slug + '/';
			var dataAt = lower.lastIndexOf(dataMarker);
			if (dataAt >= 0)
			{
				var dataDir = normalized.substr(0, dataAt) + dataMarker.substr(0, dataMarker.length - 1);
				pushCandidate(dataDir + '/events.json');
				pushCandidate(dataDir + '/event.json');
			}
		}
		// Use the active mod's resolver only after exact chart-owner paths have been checked.
		var modEvents = Paths.modFolders('data/' + slug + '/events.json');
		var modEvent = Paths.modFolders('data/' + slug + '/event.json');
		pushCandidate(modEvents);
		pushCandidate(modEvent);
		pushCandidate(Paths.getPath('data/' + slug + '/events.json'));
		pushCandidate(Paths.getPath('data/' + slug + '/event.json'));
		var eventPath:String = null;
		for (candidate in candidates)
			if (FileSystem.exists(candidate) && !FileSystem.isDirectory(candidate)) { eventPath = candidate; break; }
		if (eventPath == null) return;
		try
		{
			var root:Dynamic = Json.parse(File.getContent(eventPath));
			var separate:Dynamic = Reflect.field(root, 'events');
			if (separate == null && Reflect.field(root, 'song') != null)
				separate = Reflect.field(Reflect.field(root, 'song'), 'events');
			if (separate == null || !Std.isOfType(separate, Array)) return;
			var merged:Array<Dynamic> = [];
			var existing:Dynamic = Reflect.field(chart, 'events');
			if (existing != null && Std.isOfType(existing, Array))
				for (row in (cast existing:Array<Dynamic>))
				{
					if (row == null || !Std.isOfType(row, Array)) continue;
					var oldRow:Array<Dynamic> = cast row;
					if (oldRow.length < 2 || oldRow[1] == null || !Std.isOfType(oldRow[1], Array)) continue;
					merged.push([oldRow[0], (cast oldRow[1]:Array<Dynamic>).copy()]);
				}
			for (row in (cast separate:Array<Dynamic>))
			{
				if (row == null || !Std.isOfType(row, Array)) continue;
				var incoming:Array<Dynamic> = cast row;
				if (incoming.length < 2 || incoming[1] == null || !Std.isOfType(incoming[1], Array)) continue;
				var time = Std.parseFloat(Std.string(incoming[0]));
				if (Math.isNaN(time)) continue;
				var target:Array<Dynamic> = null;
				for (oldRow in merged)
				{
					var old:Array<Dynamic> = cast oldRow;
					var oldTime = old.length > 0 ? Std.parseFloat(Std.string(old[0])) : Math.NaN;
					if (!Math.isNaN(oldTime) && Math.abs(oldTime - time) < 0.01) { target = old; break; }
				}
				if (target == null)
				{
					target = [incoming[0], []];
					merged.push(target);
				}
				var targetSubs:Array<Dynamic> = cast target[1];
				var incomingSubs:Array<Dynamic> = cast incoming[1];
				for (sub in incomingSubs)
				{
					if (sub == null || !Std.isOfType(sub, Array)) continue;
					var incomingSub:Array<Dynamic> = cast sub;
					var encoded = Json.stringify(incomingSub);
					var duplicate = false;
					var replacedCameraAlias = false;
					var incomingComponent = incomingSub.length > 0 ? cameraEventComponent(Std.string(incomingSub[0])) : '';
					for (i in 0...targetSubs.length)
					{
						var oldSub:Dynamic = targetSubs[i];
						if (oldSub == null || !Std.isOfType(oldSub, Array)) continue;
						var old:Array<Dynamic> = cast oldSub;
						if (Json.stringify(old) == encoded) { duplicate = true; break; }
						if (incomingComponent.length == 0 || old.length == 0) continue;
						var oldComponent = cameraEventComponent(Std.string(old[0]));
						if (oldComponent != incomingComponent) continue;
						// The separate events.json is the newer canonical source when an old chart event
						// and a new built-in alias share the same component and time.
						if (editorCameraEventPriority(Std.string(incomingSub[0])) >= editorCameraEventPriority(Std.string(old[0])))
							targetSubs[i] = incomingSub.copy();
						replacedCameraAlias = true;
						break;
					}
					if (!duplicate && !replacedCameraAlias) targetSubs.push(incomingSub.copy());
				}
			}
			merged.sort(function(a:Dynamic, b:Dynamic):Int {
				var ta:Float = a != null && a.length > 0 ? Std.parseFloat(Std.string(a[0])) : 0;
				var tb:Float = b != null && b.length > 0 ? Std.parseFloat(Std.string(b[0])) : 0;
				return ta < tb ? -1 : (ta > tb ? 1 : 0);
			});
			Reflect.setField(chart, 'events', merged);
			trace('Camera Editor: merged events from ' + eventPath);
		}
		catch (e:Dynamic) trace('Camera Editor: could not load data events ' + eventPath + ': ' + Std.string(e));
	}

	#end

	/** Parse both P-Slice/Psych wrapped Chart JSON and direct song-data JSON. */
	static function parseChartJson(raw:String):Dynamic
	{
		var loaded:Dynamic = null;
		try loaded = Song.parseJSON(raw) catch (_:Dynamic) {}
		if (loaded == null || Reflect.field(loaded, "notes") == null || Reflect.field(loaded, "song") == null)
		{
			try
			{
				var root:Dynamic = Json.parse(raw);
				var inner:Dynamic = Reflect.field(root, "song");
				if (inner != null && Reflect.field(inner, "notes") != null && Reflect.field(inner, "song") != null)
					loaded = inner;
				else if (Reflect.field(root, "notes") != null && Reflect.field(root, "song") != null)
					loaded = root;
			}
			catch (_:Dynamic) {}
		}
		return loaded != null && Reflect.field(loaded, "notes") != null && Reflect.field(loaded, "song") != null ? loaded : null;
	}

	#if sys
	/** Find a chart for a song-name stored in a camera-events JSON, in the active mod. */
	function findChartInCurrentMod(songSlug:String):Dynamic
	{
		var safeSlug = Paths.formatToSongPath(songSlug);
		var dirs = [Paths.modFolders('songs/' + safeSlug)];
		var assetDir = Paths.getPath('songs/' + safeSlug);
		if (assetDir != null && assetDir.length > 0 && !dirs.contains(assetDir)) dirs.push(assetDir);
		for (dir in dirs)
		{
			if (dir == null || !FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) continue;
			var files = FileSystem.readDirectory(dir);
			var jsonFiles:Array<String> = [];
			for (f in files)
				if (camEndsWith(f.toLowerCase(), '.json') && f.toLowerCase() != 'camera_events.json') jsonFiles.push(f);
			var preferred = [safeSlug + '.json', safeSlug + '-normal.json', 'normal.json', safeSlug + '-hard.json', 'hard.json', safeSlug + '-easy.json', 'easy.json'];
			var ordered:Array<String> = [];
			for (want in preferred)
				for (f in jsonFiles)
					if (f.toLowerCase() == want.toLowerCase() && !ordered.contains(f)) ordered.push(f);
			jsonFiles.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : (a.toLowerCase() > b.toLowerCase() ? 1 : 0));
			for (f in jsonFiles) if (!ordered.contains(f)) ordered.push(f);
			for (f in ordered)
			{
				var path = haxe.io.Path.join([dir, f]);
				try
				{
					var chart = parseChartJson(File.getContent(path));
					if (chart != null) return {chart: chart, path: path};
				}
				catch (_:Dynamic) {}
			}
		}
		return null;
	}
	#end

	/** Parse and apply a real Chart JSON, then recreate this separate Editor for its song. */
	function applyChartJson(raw:String, ?sourcePath:String):Bool
	{
		var loaded:Dynamic = parseChartJson(raw);
		if (loaded == null) return false;
		var parsedSongName:String = Std.string(Reflect.field(loaded, "song"));
		if (parsedSongName.length == 0) return false;
		setPlayback(false);
		if (sourcePath != null && sourcePath.length > 0)
			Song.chartPath = sourcePath;
		// Resolve ownership for the actual chart being loaded even when the caller did not
		// pass a new path (for example, a chart selected from a data/events sidecar).
		if (Song.chartPath != null && Song.chartPath.length > 0)
			selectChartMod(Song.chartPath);
		#if sys
		mergeSeparateDataEvents(loaded, sourcePath != null ? sourcePath : Song.chartPath);
		#end
		PlayState.SONG = cast loaded;
		PlayState.isStoryMode = false;
		Song.loadedSongName = Paths.formatToSongPath(parsedSongName);
		try StageData.loadDirectory(PlayState.SONG) catch (e:Dynamic) trace('Camera Editor chart directory load: $e');
		if (PlayState.SONG.stage == null || PlayState.SONG.stage.length == 0)
			PlayState.SONG.stage = StageData.vanillaSongStage(Song.loadedSongName);
		var newSongName = Paths.formatToSongPath(parsedSongName);
		status('Chart loaded: $parsedSongName | stage: ${PlayState.SONG.stage}');
		// ห้ามเรียก stopEditorTransientSounds() ตรงนี้: state เดิมยังอัปเดตอยู่จนกว่า transition จะจบ
		// การทำลายเสียงเพลง/ตั้ง FlxG.sound.music = null ก่อนทำให้เฟรมถัดไปและ create() ของเพลงใหม่พัง (ค้าง)
		// destroy() จะล้างเสียงชั่วคราวให้เองหลัง PlayState.destroy
		MusicBeatState.switchState(new CameraEditorState(newSongName));
		return true;
	}

	/** Open a real song Chart JSON. */
	function openChart():Void
	{
		chartPicker = new FileDialogHandler();
		chartPicker.open(null, 'Open Song Chart', [new FileFilter('Song Chart JSON', '*.json')], function()
		{
			var picker = chartPicker;
			if (!applyChartJson(picker.data, picker.path)) status('ไฟล์นี้ไม่ใช่ Song Chart JSON ที่รองรับ');
			picker.destroy();
			chartPicker = null;
		}, null, function()
		{
			status('อ่าน Chart ไม่สำเร็จ');
			if (chartPicker != null) chartPicker.destroy();
			chartPicker = null;
		});
	}

	/** Convert standard Chart/events.json rows into the editor's native camera keys. Non-camera events are ignored here. */
	function cameraKeysFromEventRows(rows:Array<Dynamic>):Array<CamEvent>
	{
		var out:Array<CamEvent> = [];
		if (rows == null) return out;
		var noteOffset:Float = ClientPrefs.data.noteOffset;
		for (rowValue in rows)
		{
			if (rowValue == null || !Std.isOfType(rowValue, Array)) continue;
			var row:Array<Dynamic> = cast rowValue;
			if (row.length < 2 || row[1] == null || !Std.isOfType(row[1], Array)) continue;
			var rawTime = Std.parseFloat(Std.string(row[0]));
			if (Math.isNaN(rawTime)) continue;
			var keyTime = Math.max(0, rawTime + noteOffset);
			var stepMs = Math.max(1, Conductor.getCrotchetAtTime(keyTime) / 4);
			var subs:Array<Dynamic> = cast row[1];
			for (subValue in subs)
			{
				if (subValue == null || !Std.isOfType(subValue, Array)) continue;
				var sub:Array<Dynamic> = cast subValue;
				if (sub.length == 0) continue;
				var name = Std.string(sub[0]).trim().toLowerCase();
				var v1 = sub.length > 1 && sub[1] != null ? Std.string(sub[1]) : '';
				var v2 = sub.length > 2 && sub[2] != null ? Std.string(sub[2]) : '';
				var autoRelease = hasAutoReleaseMarker(v2);
				var parts:Array<String>;
				var n:Float;
				switch (name)
				{
					case 'focuscamera' | 'focus camera':
						var e:CamEvent = {time: keyTime, track: 'focus', x: 0, y: 0, zoom: defaultZoom, duration: 0, ease: 'linear', target: -1, autoRelease: autoRelease};
						if (v1.trim().length == 0) e.target = -2;
						else
						{
							parts = v1.split(',');
							switch (parts[0].trim().toLowerCase())
							{
								case '0' | 'bf' | 'boyfriend': e.target = 0;
								case '1' | 'dad' | 'opponent': e.target = 1;
								case '2' | 'gf' | 'girlfriend': e.target = 2;
								default: e.target = -1;
							}
							var ox = parts.length > 1 ? Std.parseFloat(parts[1]) : 0;
							var oy = parts.length > 2 ? Std.parseFloat(parts[2]) : 0;
							e.x = Math.isNaN(ox) ? 0 : ox;
							e.y = Math.isNaN(oy) ? 0 : oy;
							parts = v2.split(',');
							if (parts.length > 0 && parts[0].trim().length > 0)
							{
								var steps = Std.parseFloat(parts[0]);
								if (!Math.isNaN(steps) && steps > 0) e.duration = steps * stepMs;
								if (parts.length > 1)
								{
									var easeName = parts[1].trim();
									if (easeName.toUpperCase() == 'CLASSIC') { e.ease = 'expoOut'; e.duration += 1000; }
									else if (easeName.toUpperCase() == 'INSTANT') { e.ease = 'linear'; e.duration = 0; }
									else e.ease = easeName.length > 0 ? easeName : 'smootherStepOut';
								}
								else e.ease = 'smootherStepOut';
							}
						}
						out.push(e);
					case 'camera focus xy':
						parts = v1.split(','); if (parts.length < 2) continue;
						var x = Std.parseFloat(parts[0]); var y = Std.parseFloat(parts[1]);
						if (Math.isNaN(x) || Math.isNaN(y)) continue;
						parts = v2.split(','); var steps = parts.length > 0 ? Std.parseFloat(parts[0]) : Math.NaN;
						if (Math.isNaN(steps) || steps < 0) steps = 0;
						var easeName = parts.length > 1 && parts[1].trim().length > 0 ? parts[1].trim() : 'smootherStepOut';
						out.push({time: keyTime, track: 'focus', x: x, y: y, zoom: defaultZoom, duration: steps * stepMs, ease: easeName, target: -1, autoRelease: autoRelease});
					case 'camera follow pos' | 'camera warp pos':
						var e:CamEvent = {time: keyTime, track: 'focus', x: 0, y: 0, zoom: defaultZoom, duration: 0, ease: 'linear', target: -1};
						if (v1.trim().length == 0 && v2.trim().length == 0) e.target = -2;
						else {
							var x = Std.parseFloat(v1); var y = Std.parseFloat(v2);
							e.x = Math.isNaN(x) ? 0 : x; e.y = Math.isNaN(y) ? 0 : y;
						}
						out.push(e);
					case 'target camera':
						var e:CamEvent = {time: keyTime, track: 'focus', x: 0, y: 0, zoom: defaultZoom, duration: 0, ease: 'linear', target: -1, autoRelease: autoRelease};
						switch (v1.trim().toLowerCase()) { case '0' | 'bf' | 'boyfriend': e.target = 0; case '1' | 'dad' | 'opponent': e.target = 1; case '2' | 'gf' | 'girlfriend': e.target = 2; default: e.target = -1; }
						parts = v2.split(',');
						if (parts.length > 0) { var x = Std.parseFloat(parts[0]); if (!Math.isNaN(x)) e.x = x; }
						if (parts.length > 1) { var y = Std.parseFloat(parts[1]); if (!Math.isNaN(y)) e.y = y; }
						if (parts.length > 2) { var steps = Std.parseFloat(parts[2]); if (!Math.isNaN(steps) && steps > 0) e.duration = steps * stepMs; }
						if (parts.length > 3 && parts[3].trim().length > 0) e.ease = parts[3].trim();
					out.push(e);
					case 'set camzoom' | 'set camera zoom' | 'defaultcamzoom' | 'zoomcamera':
						n = Std.parseFloat(v1);
						if (Math.isNaN(n) || n <= 0) continue;
						var seconds = Std.parseFloat(v2.split(',')[0]);
						if (Math.isNaN(seconds) || seconds < 0) seconds = 0;
						var easeName = 'sineInOut'; parts = v2.split(','); if (parts.length > 1 && parts[1].trim().length > 0) easeName = parts[1].trim();
						out.push({time: keyTime, track: 'zoom', x: 0, y: 0, zoom: n, duration: seconds * 1000, ease: easeName, target: -1});
					case 'zoom camera':
						parts = v1.split(','); if (parts.length < 2) continue;
						var steps = Std.parseFloat(parts[0]); var scale = Std.parseFloat(parts[1]);
						if (Math.isNaN(steps)) steps = 0; if (Math.isNaN(scale) || scale <= 0) scale = 1;
						out.push({time: keyTime, track: 'zoom', x: 0, y: 0, zoom: defaultZoom * scale, duration: Math.max(0, steps) * stepMs, ease: v2.trim().length > 0 ? v2.trim() : 'linear', target: -1});
					case 'add camera zoom':
						n = Std.parseFloat(v1); if (Math.isNaN(n)) n = 0.015;
						var hn = Std.parseFloat(v2); if (Math.isNaN(hn)) hn = n * 2;
						out.push({time: keyTime, track: 'kick', x: 0, y: 0, zoom: n, hudZoom: hn, duration: 0, ease: 'linear', target: -1});
					case 'rol cam' | 'roll camera':
						n = Std.parseFloat(v1); if (Math.isNaN(n)) n = 0;
						parts = v2.split(','); var seconds = parts.length > 0 ? Std.parseFloat(parts[0]) : Math.NaN;
						if (Math.isNaN(seconds)) seconds = 1;
						var easeName = parts.length > 1 && parts[1].trim().length > 0 ? parts[1].trim() : 'quadInOut';
						out.push({time: keyTime, track: 'tilt', x: 0, y: 0, zoom: defaultZoom, duration: Math.max(0, seconds) * 1000, ease: easeName, target: -1, angle: n});
					case 'camera control':
						parts = v1.split(',');
						if (parts.length >= 2) { var x = Std.parseFloat(parts[0]); var y = Std.parseFloat(parts[1]); if (Math.isNaN(x)) x = 0; if (Math.isNaN(y)) y = 0; out.push({time: keyTime, track: 'focus', x: x, y: y, zoom: defaultZoom, duration: 0, ease: 'linear', target: -1}); }
						n = Std.parseFloat(v2); if (!Math.isNaN(n) && n > 0) out.push({time: keyTime, track: 'zoom', x: 0, y: 0, zoom: n, duration: 0, ease: 'linear', target: -1});
					default:
						// General non-camera chart events don't create a camera timeline key.
				}
			}
		}
		return out;
	}

	/** Identify native event JSON before trying the more permissive chart parser. */
	function looksLikeEventFile(raw:String):Bool
	{
		try
		{
			var root:Dynamic = Json.parse(raw);
			if (Std.isOfType(root, Array)) return true;
			if (root == null) return false;
			var rootNotes = Reflect.field(root, 'notes');
			var rootEvents = Reflect.field(root, 'events');
			var songObj = Reflect.field(root, 'song');
			if (rootNotes != null) return false;
			if (rootEvents != null && Std.isOfType(rootEvents, Array)) return true;
			if (songObj != null && Reflect.field(songObj, 'notes') == null)
			{
				var nestedEvents = Reflect.field(songObj, 'events');
				if (nestedEvents != null && Std.isOfType(nestedEvents, Array)) return true;
			}
		}
		catch (_:Dynamic) {}
		return false;
	}

	/** Open a chart, editor camera JSON, or the game's native data/<song>/events.json format. */
	function openJson():Void
	{
		jsonPicker = new FileDialogHandler();
		jsonPicker.open(null, 'Open Event File', [new FileFilter('JSON files (Chart / events.json / Camera Events)', '*.json')], function()
		{
			var picker = jsonPicker;
			var raw = picker.data;
			if (!looksLikeEventFile(raw) && applyChartJson(raw, picker.path))
			{
				picker.destroy(); jsonPicker = null; return;
			}
			try
			{
				var parsed:Dynamic = Json.parse(raw);
				var rawEvents:Dynamic = null;
				if (Std.isOfType(parsed, Array)) rawEvents = parsed;
				else if (parsed != null && Reflect.hasField(parsed, 'events') && Std.isOfType(Reflect.field(parsed, 'events'), Array)) rawEvents = Reflect.field(parsed, 'events');
				if (rawEvents == null && parsed != null && Reflect.field(parsed, 'song') != null)
				{
					var songObj = Reflect.field(parsed, 'song');
					if (songObj != null && Reflect.hasField(songObj, 'events') && Std.isOfType(Reflect.field(songObj, 'events'), Array)) rawEvents = Reflect.field(songObj, 'events');
				}
				if (rawEvents == null) throw 'JSON ไม่มี events array ที่รองรับ';
				var incoming:Array<CamEvent> = [];
				if ((cast rawEvents:Array<Dynamic>).length == 0)
					incoming = [];
				else
				{
					var first:Dynamic = (cast rawEvents:Array<Dynamic>)[0];
					if (first != null && Reflect.hasField(first, 'track'))
					{
						incoming = cast rawEvents;
						for (e in incoming)
						{
							if (e == null || (e.track != 'focus' && e.track != 'zoom' && e.track != 'tilt' && e.track != 'kick' && e.track != 'general')) throw 'track ต้องเป็น focus, zoom, tilt, kick หรือ general';
							if (e.ease == null || e.ease.length == 0) e.ease = 'linear';
							if (e.duration < 0) e.duration = 0;
						}
					}
					else incoming = cameraKeysFromEventRows(cast rawEvents);
				}
				var importedSongValue:Dynamic = Reflect.field(parsed, 'song');
				var importedSong:String = '';
				if (Std.isOfType(importedSongValue, String)) importedSong = Std.string(importedSongValue);
				else if (importedSongValue != null && Reflect.field(importedSongValue, 'song') != null) importedSong = Std.string(Reflect.field(importedSongValue, 'song'));
				var importedSlug = importedSong.length == 0 ? '' : Paths.formatToSongPath(importedSong);
				#if sys
				if (importedSlug.length > 0 && importedSlug != Paths.formatToSongPath(songName))
				{
					var found = findChartInCurrentMod(importedSlug);
					if (found != null)
					{
						PlayState.SONG = cast found.chart;
						Song.loadedSongName = importedSlug;
						if (PlayState.SONG.stage == null || PlayState.SONG.stage.length == 0) PlayState.SONG.stage = StageData.vanillaSongStage(importedSlug);
						try Reflect.setProperty(Song, 'chartPath', found.path) catch (_:Dynamic) {}
						pendingImportedEvents = incoming;
						setPlayback(false);
						MusicBeatState.switchState(new CameraEditorState(importedSlug));
						picker.destroy(); jsonPicker = null; return;
					}
					status('เปิด Events ได้ แต่ไม่พบ Chart ของ ' + importedSlug + ' ใน Mod ที่เลือก');
				}
				#end
				events = incoming;
				normalizeDuplicateEditorKeys();
				readLayerCounts(parsed);
				sortEvents(); selected = null; history = []; redoStack = [];
				status('เปิด Event File สำเร็จ: โหลดคีย์กล้อง ' + events.length + ' รายการ (อีเวนต์ทั่วไปคงเป็นข้อมูล Chart)');
			}
			catch (err) status('เปิด Event File ไม่สำเร็จ: ' + Std.string(err));
			picker.destroy(); jsonPicker = null;
		}, null, function()
		{
			status('อ่าน Event File ไม่สำเร็จ');
			if (jsonPicker != null) jsonPicker.destroy();
			jsonPicker = null;
		});
	}

	function playTest()
	{
		setPlayback(false);
		doSave(false, false); // PlayTest: เตรียม camera + non-camera events ในหน่วยความจำเท่านั้น ไม่เขียนไฟล์
		autosaveBackup(false);
		exitBackupDone = true;
		PlayState.isStoryMode = false;
		PlayState.chartingMode = false;
		if (returnToEditorMenu)
		{
			// A playtest enters gameplay, so the paused menu track must not be restored later.
			editorMenuMusic = null;
			editorMenuMusicWasPlaying = false;
			editorMenuMusicCaptured = false;
			returnToEditorMenu = false;
		}
		// Leave this editor page and run the selected chart with the saved camera events.
		if (PlayState.SONG != null)
		{
			returnToCameraEditorAfterPlayTest = true;
			stopEditorTransientSounds();
			MusicBeatState.switchState(new PlayState());
		}
		else
			status("ไม่มีเพลงให้ PlayTest");
	}

	/** Stop one-shot or persistent sounds created after the editor was opened. */
	function stopEditorTransientSounds():Void
	{
		var activeSounds = FlxG.sound.list.members.copy();
		for (sound in activeSounds)
		{
			if (sound == null || soundsBeforeEditor.indexOf(sound) >= 0 || sound == editorMenuMusic)
				continue;
			if (FlxG.sound.music == sound) FlxG.sound.music = null;
			sound.stop();
			FlxG.sound.list.remove(sound);
			sound.destroy();
		}
	}

	function exitEditor()
	{
		autosaveBackup(false); // ออกจาก editor: เก็บ backup ล่าสุดไว้ก่อน (ถ้ามีอะไรเปลี่ยนจากรอบที่แล้ว)
		exitBackupDone = true;
		stopPreview();
		stopEditorTransientSounds();
		if (returnToGameplay && PlayState.SONG != null)
			MusicBeatState.switchState(new PlayState());
		else if (returnToEditorMenu)
		{
			restoreMenuMusicAfterDestroy = true;
			MusicBeatState.switchState(new MasterEditorMenu());
		}
		else
			MusicBeatState.switchState(new mikolka.vslice.ui.MainMenuState());
	}

	static function restoreEditorMenuMusic():Void
	{
		if (editorMenuMusic != null)
		{
			editorMenuMusic.volume = editorMenuMusicVolume;
			FlxG.sound.music = editorMenuMusic;
			if (editorMenuMusicWasPlaying)
			{
				editorMenuMusic.time = editorMenuMusicTime;
				editorMenuMusic.play();
			}
		}
		editorMenuMusic = null;
		editorMenuMusicWasPlaying = false;
		editorMenuMusicCaptured = false;
	}

	function status(s:String)
		setTextIfChanged(statusText, s);

	// =====================================================================
	//  Playback
	// =====================================================================
	function togglePlay()
	{
		setPlayback(!playing);
	}

	function finishPreviewSong():Void
	{
		// This callback is invoked from FlxSound's own update/onComplete path. Do not replay
		// the same FlxSound here: FlxSound will finish marking it stopped after this callback
		// returns, cancelling an immediate play(). Resolve the end on CameraEditorState.update.
		if (createFailed || previewEndPending) return;
		previewEndPending = true;
	}

	function resolvePreviewSongEnd():Void
	{
		if (!previewEndPending) return;
		previewEndPending = false;
		var shouldLoop:Bool = playing && !createFailed;

		if (!scriptSongEnded && stageHost != null)
		{
			scriptSongEnded = true;
			try stageHost.callOnScripts('onSongEnd') catch (e:Dynamic) trace('Camera Editor onSongEnd: $e');
		}

		// Restart only after the finished FlxSound update has completely unwound. Reset the
		// transport, callbacks, chart events, Lua tweens/timers, characters, and camera before
		// deciding whether playback should continue.
		playing = false;
		pauseCameraEditorPlayback();
		rewindPreviewAudio();
		seekTo(0);
		if (stageHost != null && generatedMusic)
			replayEventsTo(0);
		lastPreviewTime = 0;

		if (shouldLoop)
		{
			pauseHold = false;
			setPlayback(true);
			status('เพลงจบแล้ว: รีเซ็ต Lua/Events แล้ววนเล่นต่อ (กด Stop เพื่อหยุด)');
		}
		else
		{
			pauseHold = false;
			status('เพลงจบแล้ว: รีเซ็ตกลับต้นเพลง กด Play เพื่อเล่นต่อ');
		}
	}
	function rewindPreviewAudio():Void
	{
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		}
		if (vocals != null)
		{
			vocals.pause();
			vocals.time = 0;
		}
		if (opponentVocals != null)
		{
			opponentVocals.pause();
			opponentVocals.time = 0;
		}
	}

	function setPlayback(doPlay:Bool):Void
	{
		if (doPlay == playing) return;
		if (doPlay) pauseHold = false;
		if (doPlay) holdInitialStart = false; // ผู้ใช้สั่งเล่นเองแล้ว เลิกบังคับหยุดตอนเปิด editor
		if (doPlay && songPos >= songLen)
			seekTo(0);
		var wasPlaying = playing;
		var wasSongStarted = scriptSongStarted;
		playing = doPlay;
		if (doPlay)
		{
			#if VIDEOS_ALLOWED
			if (previewEventVideo != null) previewEventVideo.resume();
			#end
			snapGameCameraToTimeline();
			var startsNatively = startingSong; // startSong() ของ PlayState จะเรียก onSongStart เอง (เล่นครั้งแรก)
			startCameraEditorPlayback(songPos);
			scriptSongStarted = true;
			// เล่นใหม่จากต้นเพลงหลังรีเซ็ต: PlayState ไม่เรียก startSong ซ้ำ จึงเรียก onSongStart ให้ Lua ตั้งค่าเริ่มต้นอีกรอบ
			if (!startsNatively && songStartPending && songPos <= 1 && stageHost != null)
				try stageHost.callOnScripts('onSongStart') catch (e:Dynamic) trace('Camera Editor onSongStart: $e');
			songStartPending = false;
			songStartedOnce = true;
		}
		else
		{
			#if VIDEOS_ALLOWED
			if (previewEventVideo != null) previewEventVideo.pause();
			#end
			if (wasPlaying)
			{
				// ค้าง VCam ไว้ที่กล้องจริง ณ ตอนที่กดหยุด
				pauseHoldPose = {x: vcamPose.x, y: vcamPose.y, zoom: vcamPose.zoom};
				pauseHold = true;
			}
			pauseCameraEditorPlayback();
		}
		if (stageHost != null)
		{
			if (doPlay && !wasPlaying && wasSongStarted)
				try stageHost.callOnScripts('onResume') catch (e:Dynamic) trace('Camera Editor onResume: $e');
			else if (!doPlay && wasPlaying)
				try stageHost.callOnScripts('onPause') catch (e:Dynamic) trace('Camera Editor onPause: $e');
		}
	}

	/** Find audio beside a user-selected chart or in its usual sibling songs/<slug> folder. */
	public static function findChartSidecarAudio(songName:String, fileNames:Array<String>, ?ownedSounds:Array<Sound>):Sound
	{
		#if sys
		var chartPath = Song.chartPath;
		if (chartPath != null && chartPath.length > 0 && songName != null)
		{
			var normalized = chartPath.split('\\').join('/');
			var directory = haxe.io.Path.directory(normalized);
			var slug = Paths.formatToSongPath(songName);
			var directories:Array<String> = [];
			if (directory != null && directory.length > 0) directories.push(directory);
			var ancestor = directory;
			for (_ in 0...6)
			{
				if (ancestor == null || ancestor.length == 0 || ancestor == '.') break;
				var songFolder = haxe.io.Path.join([ancestor, 'songs', slug]);
				if (!directories.contains(songFolder)) directories.push(songFolder);
				var directSongFolder = haxe.io.Path.join([ancestor, slug]);
				if (!directories.contains(directSongFolder)) directories.push(directSongFolder);
				var parent = haxe.io.Path.directory(ancestor);
				if (parent == ancestor) break;
				ancestor = parent;
			}
			for (dir in directories)
				for (fileName in fileNames)
				{
					var candidate = haxe.io.Path.join([dir, fileName]);
					if (FileSystem.exists(candidate) && !FileSystem.isDirectory(candidate))
					{
						try
						{
							var sound = Sound.fromFile(candidate);
							if (ownedSounds != null) ownedSounds.push(sound);
							return sound;
						}
						catch (e:Dynamic) trace('Camera Editor audio $candidate: $e');
					}
				}
		}
		#end
		return null;
	}

	function addFocusEvent():Void
	{
		var cam = evalAt(songPos);
		addEvent({time: songPos, track: 'focus', x: cam.x, y: cam.y, zoom: cam.zoom, duration: 500, ease: 'quadOut', target: -1,
			layer: freeLayer('focus', songPos, 500)});
	}

	function addZoomEvent():Void
	{
		var cam = evalAt(songPos);
		addEvent({time: songPos, track: 'zoom', x: cam.x, y: cam.y, zoom: cam.zoom, duration: 500, ease: 'quadOut', target: -1,
			layer: freeLayer('zoom', songPos, 500)});
	}

	function addTiltEvent():Void
	{
		var cam = evalAt(songPos);
		addEvent({time: songPos, track: 'tilt', x: 0, y: 0, zoom: cam.zoom, duration: 1000, ease: 'quadInOut', target: -1,
			layer: freeLayer('tilt', songPos, 1000), angle: evalAngleAt(songPos)});
	}

	function seekTo(t:Float)
	{
		stopPreviewEventVideo();
		songPos = Math.max(0, Math.min(songLen, t));
		pauseHold = false;
		songStartPending = songStartedOnce && songPos <= 1;
		// Use PlayState's live audio streams and timeline; no second preview player exists.
		seekCameraEditorPlayback(songPos);
		// PlayState.beatHit/stepHit ข้ามทุกอย่างถ้า curBeat <= lastBeatHit (ใช้กันซ้ำตอนเล่นไปข้างหน้า)
		// พอย้อนกลับ lastBeatHit ยังค้างที่บีตสูงสุดเดิม GF (ที่เต้นผ่าน beatHit อย่างเดียว) จึงนิ่งไปจนเพลงเดินเลยจุดนั้น
		// รวมถึง onBeatHit ของ Lua และ camera bop ด้วย จึงต้องย้ายตัวนับไปไว้ก่อนตำแหน่งใหม่
		lastBeatHit = Std.int(Math.floor(Conductor.getBeat(songPos))) - 1;
		lastStepHit = Std.int(Math.floor(Conductor.getStep(songPos))) - 1;
		eventReplayPending = true;
		syncCameraEvents();
		scriptCameraFollowOverride = false;
		scriptCameraZoomOverride = false;
		scriptCameraForced = false;
		lastSyncedFollowX = Math.NaN;
		lastSyncedFollowY = Math.NaN;
		lastSyncedZoom = Math.NaN;
		resetVcamDiagnostics();
		if (songPos <= 0 && scriptSongEnded)
		{
			scriptSongStarted = false;
			scriptSongEnded = false;
		}
	}

	function clampTimelineScroll():Void
	{
		var visibleMs = Math.max(1, (FlxG.width - TL_X) / pps * 1000);
		var maxScroll = Math.max(0, songLen - visibleMs);
		scrollMs = Math.max(0, Math.min(maxScroll, scrollMs));
	}

	// =====================================================================
	//  Coordinate helpers
	// =====================================================================
	inline function timeAt(px:Float):Float
		return Math.max(0, Math.min(songLen, scrollMs + (px - TL_X) / pps * 1000));

	inline function xAt(t:Float):Float
		return TL_X + (t - scrollMs) * pps / 1000;

	inline function inRect(mx:Float, my:Float, x:Float, y:Float, w:Float, h:Float):Bool
		return mx >= x && mx < x + w && my >= y && my < y + h;

	inline function layerOf(e:CamEvent):Int
		return e.layer == null ? 0 : e.layer;

	inline function angleOf(e:CamEvent):Float
		return e.angle == null ? 0 : e.angle;

	inline function rowCount():Int
		return focusLayers + zoomLayers + tiltLayers + 1; // Focus + Zoom + Tilt + General

	/** ความสูงแถวย่อลงอัตโนมัติเมื่อเพิ่มเลเยอร์ เพื่อให้ timeline ไม่ทับ status bar */
	inline function rowH():Int
		return TRACK_H;

	inline function previewPanelHeight():Int
		return Std.int(Math.max(MIN_PREVIEW_PANEL_H, timelineTopY - PREV_Y - PREVIEW_TIMELINE_GAP));

	inline function tlHeight():Int
		return Std.int(Math.max(RULER_H + rowH(), Math.min(TL_BOTTOM - timelineTopY, timelinePanelHeight)));

	inline function visibleTimelineRows():Int
		return Std.int(Math.max(1, Math.min(rowCount(), Math.floor((tlHeight() - RULER_H) / rowH()))));

	function maxLayerScroll():Float
		return Math.max(0, rowH() * (rowCount() - visibleTimelineRows()));

	function timelineFollowButtonRect():{x:Float, y:Float, w:Float, h:Float}
	{
		// Reserve space on the right for curStep so the two controls never overlap.
		var stepWidth = Math.max(105, curStepText == null ? 105 : curStepText.width);
		var x = FlxG.width - stepWidth - 16 - 12 - 220;
		return {x: Math.max(8, x), y: 684, w: 220, h: 22};
	}

	/** Center the grips over the usable timeline, but keep them clear of the right-hand event list. */
	inline function timelineGripCenter():Float
		return Math.min((TL_X + FlxG.width) * 0.5, PANEL_X - 96);

	/** Invisible hit zone is intentionally larger than the visible handle for reliable grabbing. */
	function timelineTopGripRect():{x:Float, y:Float, w:Float, h:Float}
		return {x: timelineGripCenter() - 82, y: timelineTopY - 10, w: 164, h: 14};

	/** The bottom grip sits entirely below the tracks, so the final event row remains clickable. */
	function timelineBottomGripRect():{x:Float, y:Float, w:Float, h:Float}
		return {x: timelineGripCenter() - 76, y: timelineTopY + tlHeight(), w: 152, h: 12};

	function cycleTimelineFollow(delta:Int = 1):Void
	{
		timelineFollowMode = (timelineFollowMode + delta + TIMELINE_FOLLOW_LABELS.length) % TIMELINE_FOLLOW_LABELS.length;
		lastTimelineFollowStep = -1;
		status('Timeline follow: ' + TIMELINE_FOLLOW_LABELS[timelineFollowMode]);
	}

	function updateTimelineFollow():Void
	{
		if (!playing || timelineFollowMode == 3) return;
		var step = Std.int(Math.floor(Conductor.getStep(songPos)));
		var followX = TL_X + (FlxG.width - TL_X) * 0.72;
		var playheadX = xAt(songPos);
		switch (timelineFollowMode)
		{
			case 0: // Realtime: smoothly keep the playhead around 72% of the visible timeline.
				if (playheadX >= followX)
				{
					scrollMs = songPos - (followX - TL_X) / pps * 1000;
					clampTimelineScroll();
				}
			case 1: // 4-step mode: move the viewport only on a four-step boundary.
				if (playheadX >= followX && step >= 0 && step % 4 == 0 && step != lastTimelineFollowStep)
				{
					scrollMs = songPos - (followX - TL_X) / pps * 1000;
					lastTimelineFollowStep = step;
					clampTimelineScroll();
				}
			case 2: // At Edge: keep the old behavior and scroll only when playhead nears the right edge.
				if (playheadX > FlxG.width - 40)
				{
					scrollMs = songPos - (FlxG.width - TL_X - 40) / pps * 1000;
					clampTimelineScroll();
				}
			default:
		}
	}

	function clampLayerScroll():Void
		layerScrollY = Math.max(0, Math.min(maxLayerScroll(), layerScrollY));

	function trackY(track:String, layer:Int = 0):Int
	{
		var l = layer < 0 ? 0 : layer;
		var row:Int;
		if (track == "focus") row = Std.int(Math.min(l, focusLayers - 1));
		else if (track == "zoom" || track == "kick") row = focusLayers + Std.int(Math.min(l, zoomLayers - 1));
		else if (track == "tilt") row = focusLayers + zoomLayers + Std.int(Math.min(l, tiltLayers - 1));
		else row = focusLayers + zoomLayers + tiltLayers; // general
		return timelineTopY + RULER_H + row * rowH() - Std.int(layerScrollY);
	}

	/** แถว (track + layer) ที่อยู่ใต้ตำแหน่ง y หรือ null ถ้าไม่ได้อยู่บนแถวไหน */
	function rowAt(my:Float):{track:String, layer:Int}
	{
		if (my < timelineTopY + RULER_H || my >= timelineTopY + tlHeight()) return null;
		var rel = my - timelineTopY - RULER_H + layerScrollY;
		if (rel < 0) return null;
		var row = Std.int(rel / rowH());
		if (row >= rowCount()) return null;
		if (row < focusLayers) return {track: "focus", layer: row};
		if (row < focusLayers + zoomLayers) return {track: "zoom", layer: row - focusLayers};
		if (row < focusLayers + zoomLayers + tiltLayers) return {track: "tilt", layer: row - focusLayers - zoomLayers};
		return {track: "general", layer: 0};
	}

	/** เลเยอร์แรกที่ช่วงเวลานี้ยังว่างอยู่ (ไม่มีให้ใช้ = 0) */
	function freeLayer(track:String, time:Float, duration:Float):Int
	{
		var count = layerCountOf(track);
		var end = time + Math.max(duration, 1);
		for (l in 0...count)
		{
			var busy = false;
			for (e in events)
				if (e.track == track && layerOf(e) == l && e.time < end && e.time + Math.max(e.duration, 1) > time)
				{
					busy = true;
					break;
				}
			if (!busy) return l;
		}
		return 0;
	}

	/** จำนวนเลเยอร์ไม่เคยน้อยกว่าที่ event ใช้อยู่ (และไม่เกินเพดาน) */
	function recountLayers():Void
	{
		for (e in events)
		{
			if (layerOf(e) >= MAX_LAYERS_PER_TRACK) e.layer = MAX_LAYERS_PER_TRACK - 1;
			var needed = layerOf(e) + 1;
			if (e.track == "focus")
			{
				if (needed > focusLayers) focusLayers = needed;
			}
			else if (e.track == "tilt")
			{
				if (needed > tiltLayers) tiltLayers = needed;
			}
			else if (needed > zoomLayers) zoomLayers = needed;
		}
	}

	function layerCountOf(track:String):Int
		return track == "focus" ? focusLayers : (track == "tilt" ? tiltLayers : zoomLayers);

	function trackTitle(track:String):String
		return track == "focus" ? "Focus" : (track == "tilt" ? "Tilt" : "Zoom");

	function addLayer(track:String):Void
	{
		var count = layerCountOf(track);
		if (count >= MAX_LAYERS_PER_TRACK)
		{
			status('เพิ่มเลเยอร์ไม่ได้: ${trackTitle(track)} มีได้สูงสุด $MAX_LAYERS_PER_TRACK เลเยอร์');
			return;
		}
		if (track == "focus") focusLayers++;
		else if (track == "tilt") tiltLayers++;
		else zoomLayers++;
		clampLayerScroll();
		status('เพิ่มเลเยอร์ ${trackTitle(track)} ${count + 1} แล้ว');
	}

	function removeLayer(track:String):Void
	{
		var count = layerCountOf(track);
		if (count <= 1)
		{
			status('ต้องเหลืออย่างน้อย 1 เลเยอร์');
			return;
		}
		var top = count - 1;
		for (e in events)
			if (e.track == track && layerOf(e) == top)
			{
				status('เลเยอร์ ${top + 1} ยังมี key อยู่ ย้ายหรือลบ key ก่อนค่อยลบเลเยอร์');
				return;
			}
		if (track == "focus") focusLayers--;
		else if (track == "tilt") tiltLayers--;
		else zoomLayers--;
		clampLayerScroll();
		status('ลบเลเยอร์ ${trackTitle(track)} ${count} แล้ว');
	}

	function layerButtonRect(group:Int, minus:Bool):{x:Float, y:Float, w:Float, h:Float}
	{
		var rh = rowH();
		var firstRow = group == 0 ? 0 : (group == 1 ? focusLayers : focusLayers + zoomLayers);
		var groupRows = group == 0 ? focusLayers : (group == 1 ? zoomLayers : tiltLayers);
		var viewTop = timelineTopY + RULER_H;
		var viewBottom = timelineTopY + tlHeight();
		// ปุ่มค้างอยู่ในช่วงที่มองเห็นของกลุ่ม (เลื่อนเลเยอร์แล้วยังกด +/- ได้) ซ่อนเมื่อกลุ่มพ้นจอ
		var groupTop = viewTop + firstRow * rh - Std.int(layerScrollY);
		var top = Math.max(groupTop, viewTop);
		var bottom = Math.min(groupTop + groupRows * rh, viewBottom);
		var bh = Math.min(16, rh - 4);
		return {
			x: TL_X - (minus ? 22 : 42),
			y: top + 2,
			w: 18,
			h: bottom - top >= bh + 4 ? bh : 0
		};
	}

	function handleLayerButtons(mx:Float, my:Float):Bool
	{
		for (group in 0...3)
			for (minus in [false, true])
			{
				var r = layerButtonRect(group, minus);
				if (r.h <= 0 || !inRect(mx, my, r.x, r.y, r.w, r.h)) continue;
				var track = group == 0 ? "focus" : (group == 1 ? "zoom" : "tilt");
				if (minus) removeLayer(track);
				else addLayer(track);
				return true;
			}
		return false;
	}

	/** Snap ตาม Step ของเพลง (1/4 บีต ตาม BPM map ของ Conductor) กด Alt ค้างเพื่อปิด snap */
	function snap(t:Float):Float
	{
		if (!snapEnabled || FlxG.keys.pressed.ALT) return t;
		try
		{
			var snapped:Float = Conductor.beatToSeconds(Math.round(Conductor.getStep(t)) / 4);
			if (!Math.isNaN(snapped) && snapped >= 0) return snapped;
		}
		catch (_:Dynamic) {}
		return Math.round(t / 50) * 50;
	}

	// ---------- multi-select / clipboard / zoom buttons ----------
	// ---------- Properties panel (แผงคุณสมบัติของอีเวนต์ที่เลือก) ----------
	static inline var PROP_BOX_X = 104; // wider numeric controls; shorter labels keep the inspector balanced

	/** ตอนหยุด: ถ้า key อยู่ "หลัง" playhead VCam จะยังไม่เห็นผล จึงเลื่อน playhead ไปท้าย key เพื่อให้ VCam แสดงผลลัพธ์ทันที */
	function previewKey(e:CamEvent):Void
	{
		if (e == null || playing || (events.indexOf(e) < 0 && chartCameraEvents.indexOf(e) < 0) || e.track == 'kick') return;
		// At exactly e.time a non-zero-duration tween is still at its FROM value.
		// Preview the completed pose whenever the playhead is before this key's end,
		// including the common time=0 case, so values such as zoom=0.2 are visible.
		var previewEnd = Math.min(songLen, e.time + Math.max(0, e.duration));
		if (songPos < previewEnd - 0.001) seekTo(previewEnd);
	}

	function propLayout():Array<{key:String, label:String, y:Float, h:Float}>
	{
		var out:Array<{key:String, label:String, y:Float, h:Float}> = [];
		if (selected == null || (events.indexOf(selected) < 0 && chartCameraEvents.indexOf(selected) < 0)) return out;
		// Native camera properties always use the same layout. Legacy Value1/Value2
		// editors have been removed, so never reserve their old fixed-position rows here.
		var y:Float = PREV_Y + 246;
		var h:Float = 28;
		var add = function(key:String, label:String, ?height:Float)
		{
			var rowH = height == null ? h : height;
			out.push({key: key, label: label, y: y, h: rowH});
			y += rowH;
		};
		switch (selected.track)
		{
			case 'focus':
				add('time', 'Time (ms)');
				if (selected.target != -2) // Release = ปล่อยกล้องทันที ไม่มีตำแหน่ง/ระยะเวลา/Ease
				{
					add('duration', 'Duration (ms)');
					add('x', selected.target >= 0 ? 'Offset X' : 'Position X');
					add('y', selected.target >= 0 ? 'Offset Y' : 'Position Y');
				}
				add('target', 'Target');
				if (selected.target != -2) add('ease', 'Ease');
			case 'zoom':
				add('time', 'Time (ms)');
				add('duration', 'Duration (ms)');
				add('zoom', 'Zoom');
				add('zoomslider', '', 20);
				add('ease', 'Ease');
			case 'kick':
				add('time', 'Time (ms)');
				add('zoom', 'Zoom amount');
			case 'tilt':
				add('time', 'Time (ms)');
				add('duration', 'Duration (ms)');
				add('angle', 'Angle (deg)');
				add('tiltslider', '', 20);
				add('ease', 'Ease');
			case 'general':
				add('time', 'Time');
				add('target', 'Target');
			default:
		}
		return out;
	}

	function fmtPrecise(ms:Float):String
	{
		var total = Std.int(ms);
		var m = Std.int(total / 60000);
		var sc = Std.int((total % 60000) / 1000);
		var milli = total % 1000;
		return m + ':' + (sc < 10 ? '0' : '') + sc + '.' + (milli < 10 ? '00' : (milli < 100 ? '0' : '')) + milli;
	}

	function propValueText(key:String):String
	{
		var e = selected;
		return switch (key)
		{
			case 'time': Std.string(Math.round(e.time * 100) / 100) + ' ms';
			case 'duration': Std.int(e.duration) + ' ms';
			case 'zoom': Std.string(Math.round(e.zoom * 10000) / 10000);
			case 'angle': Std.string(Math.round(angleOf(e) * 10) / 10) + ' deg';
			case 'x': Std.string(Math.round(e.x * 10) / 10);
			case 'y': Std.string(Math.round(e.y * 10) / 10);
			case 'target': e.target == -2 ? 'Release' : (e.target >= 0 && e.target < 3 ? TARGET_NAMES[e.target + 1] : 'custom');
			case 'ease': e.ease;
			default: '';
		};
	}

	/** ปรับค่าคุณสมบัติของอีเวนต์ที่เลือก (ล้อเมาส์ / ลูกศร): dir = +1/-1, mult = ตัวคูณขั้น (Shift x5, Alt x0.1) */
	function adjustProp(key:String, dir:Int, mult:Float):Void
	{
		if (selected == null || dir == 0) return;
		var e = selected;
		var old = copyEv(e);
		switch (key)
		{
			case 'time':
				e.time = Math.max(0, Math.min(Math.max(0, songLen - e.duration), e.time + dir * 10 * mult));
				if (events.indexOf(e) >= 0) sortEvents();
			case 'duration':
				e.duration = Math.max(0, Math.min(Math.max(0, songLen - e.time), e.duration + dir * 50 * mult));
			case 'zoom':
				var zoomStep = e.track == 'kick' ? 0.001 : 0.01;
				e.zoom = Math.max(e.track == 'kick' ? 0 : 0.01, Math.min(5, Math.round((e.zoom + dir * zoomStep * mult) * 10000) / 10000));
			case 'angle':
				e.angle = Math.max(-3600, Math.min(3600, Math.round((angleOf(e) + dir * mult) * 10) / 10));
			case 'x', 'y':
				if (selectedChartSource != null && e.target >= 0
					&& (selectedChartSource.name.toLowerCase() == 'focuscamera' || selectedChartSource.name.toLowerCase() == 'focus camera'))
				{
					var absolute = resolveXY(e);
					e.target = -1;
					e.x = absolute[0];
					e.y = absolute[1];
				}
				if (key == 'x') e.x += dir * 1 * mult;
				else e.y += dir * 1 * mult;
			case 'target':
				if (e.track == 'general')
				{
					e.target = ((e.target + dir) % 3 + 3) % 3;
					e.x = e.y = 0;
				}
				else
				{
					var oi = TARGET_ORDER.indexOf(e.target);
					applyTargetTo(e, TARGET_ORDER[((oi + dir) % TARGET_ORDER.length + TARGET_ORDER.length) % TARGET_ORDER.length]); // custom -> BF -> Opp -> GF -> Release
				}
			case 'ease':
				e.ease = EASES[((EASES.indexOf(e.ease) + dir) % EASES.length + EASES.length) % EASES.length];
			default:
				return;
		}
		commitEdit(e, old);
		previewKey(e);
	}

	function setZoomFromPropSlider(mx:Float):Void
	{
		if (selected == null || selected.track != 'zoom') return;
		var t = Math.max(0, Math.min(1, (mx - (PANEL_X + 14)) / (PANEL_W - 28)));
		// Quadratic response gives much finer control around small zoom values (0.01–5.00).
		var z = 0.01 + t * t * 4.99;
		z = Math.round(z * 1000) / 1000;
		var old = copyEv(selected);
		selected.zoom = z;
		commitEdit(selected, old);
	}

	function setTiltFromPropSlider(mx:Float):Void
	{
		if (selected == null || selected.track != 'tilt') return;
		var t = Math.max(0, Math.min(1, (mx - (PANEL_X + 14)) / (PANEL_W - 28)));
		var a = -180 + t * 360;
		var near = Math.round(a / 5) * 5; // ดูดเข้าค่าที่ใช้บ่อย (ทีละ 5 องศา)
		a = Math.abs(a - near) < 2 ? near : Math.round(a * 10) / 10;
		var old = copyEv(selected);
		selected.angle = a;
		commitEdit(selected, old);
	}

	function setPropSliderFromMouse(mx:Float):Void
	{
		if (selected != null && selected.track == 'tilt') setTiltFromPropSlider(mx);
		else setZoomFromPropSlider(mx);
	}

	// =====================================================================
	//  Key editor window  /  drop-down popups  /  ease preview  /  Warp & Release
	// =====================================================================

	function keyWindowSupported():Bool
		return selected != null && (selected.track == 'focus' || selected.track == 'zoom' || selected.track == 'tilt' || selected.track == 'kick' || selected.track == 'general');

	inline function kwX():Float
		return PREV_X + (PREV_W - KW_W) * 0.5;

	inline function kwY():Float
		return PREV_Y + 10;

	function showEaseSection():Bool
		return selected != null && ((selected.track == 'focus' && selected.target != -2) || selected.track == 'zoom' || selected.track == 'tilt');

	function createKeyWindowUI():Void
	{
		for (i in 0...44)
		{
			var t = new FlxText(0, 0, 0, '', 11);
			t.color = th(0xFFE3E8EF);
			t.cameras = [editorUICamera];
			t.visible = false;
			kwTexts.push(t);
			add(t);
		}
		for (i in 0...16)
		{
			var t = new FlxText(0, 0, 0, '', 11);
			t.color = th(0xFFE3E8EF);
			t.cameras = [editorUICamera];
			t.visible = false;
			ddRows.push(t);
			add(t);
		}
		for (i in 0...2)
		{
			var t = new FlxText(0, 0, 0, '', 11);
			t.color = th(0xFFFFFFFF);
			t.cameras = [editorUICamera];
			t.visible = false;
			panelBtnTexts.push(t);
			add(t);
		}
		editBtnText = new FlxText(0, 0, 0, 'Edit...', 11);
		editBtnText.color = th(0xFFFFFFFF);
		editBtnText.cameras = [editorUICamera];
		editBtnText.visible = false;
		add(editBtnText);
		for (key in ['time', 'duration', 'x', 'y', 'zoom', 'angle'])
		{
			kwInputs.set(key, makeNumInput(key, KW_FW - 52));
			panelInputs.set(key, makeNumInput(key, PANEL_W - PROP_BOX_X - 12 - 56));
		}
	}

	function makeNumInput(key:String, width:Int):PsychUIInputText
	{
		var inp = new PsychUIInputText(0, 0, width, '', 10);
		inp.cameras = [editorUICamera];
		inp.exists = false;
		inp.onChange = function(_, _)
		{
			if (!updatingNumInputs) numInputChanged(key, inp);
		};
		add(inp);
		return inp;
	}

	function numInputChanged(key:String, inp:PsychUIInputText):Void
	{
		if (selected == null || inp.text == null) return;
		var v = Std.parseFloat(inp.text.split(',').join('.'));
		if (Math.isNaN(v)) return; // กำลังพิมพ์ค้างอยู่ เช่น "-" หรือ ""
		setPropValue(key, v);
	}

	function numText(key:String):String
	{
		if (selected == null) return '';
		var e = selected;
		var v:Float = switch (key)
		{
			case 'time': e.time;
			case 'duration': e.duration;
			case 'zoom': e.zoom;
			case 'angle': angleOf(e);
			case 'x': e.x;
			case 'y': e.y;
			default: 0;
		};
		var scale = key == 'zoom' ? 10000.0 : 1000.0;
		return Std.string(Math.round(v * scale) / scale);
	}

	/** อัปเดตข้อความในช่องพิมพ์ให้ตรงกับค่าจริง แต่ไม่แตะช่องที่ผู้ใช้กำลังพิมพ์อยู่ */
	function syncNumInput(inp:PsychUIInputText, key:String):Void
	{
		if (PsychUIInputText.focusOn == inp) return;
		var want = numText(key);
		if (inp.text != want)
		{
			updatingNumInputs = true;
			inp.text = want;
			updatingNumInputs = false;
		}
	}

	function showInput(inp:PsychUIInputText, x:Float, y:Float):Void
	{
		inp.exists = true;
		if (inp.x != x || inp.y != y) inp.setPosition(x, y);
	}

	function hideInput(inp:PsychUIInputText):Void
	{
		if (!inp.exists) return;
		if (PsychUIInputText.focusOn == inp) PsychUIInputText.focusOn = null;
		inp.exists = false;
	}

	/** ตั้งค่าตัวเลขที่พิมพ์เองลงใน key ที่เลือก (ผ่าน commitEdit จึง Undo/Redo และเขียนกลับ Chart ได้เหมือนเดิม) */
	function setPropValue(key:String, v:Float):Void
	{
		if (selected == null) return;
		var e = selected;
		var old = copyEv(e);
		switch (key)
		{
			case 'time':
				e.time = Math.max(0, Math.min(Math.max(0, songLen - e.duration), v));
			case 'duration':
				e.duration = Math.max(0, Math.min(Math.max(0, songLen - e.time), v));
				if (e.duration > 0) kwLastDuration = e.duration;
			case 'zoom':
				e.zoom = Math.max(e.track == 'kick' ? 0 : 0.01, Math.min(5, v));
			case 'angle':
				e.angle = Math.max(-3600, Math.min(3600, v));
			case 'x':
				e.x = v;
			case 'y':
				e.y = v;
			default:
				return;
		}
		commitProp(e, old);
	}

	function commitProp(e:CamEvent, old:CamEvent):Void
	{
		if (events.indexOf(e) >= 0) sortEvents(); // เปลี่ยน time / target แล้ว cache ต้องสร้างใหม่
		else
		{
			cameraEventCacheDirty = true;
			cameraEventListDirty = true;
		}
		commitEdit(e, old);
		previewKey(e);
	}

	/** เปลี่ยน target ของ key: custom(-1) / BF(0) / Opp(1) / GF(2) / Release(-2 = ปล่อยกล้องกลับไปตามปกติ) */
	function applyTargetTo(e:CamEvent, t:Int):Void
	{
		if (e.track == 'general')
		{
			e.target = Std.int(Math.max(0, Math.min(2, t)));
			e.x = 0;
			e.y = 0;
			return;
		}
		var wasRelease = e.target == -2;
		var cur:Array<Float>;
		if (wasRelease)
		{
			var c = evalAt(Math.max(0, e.time - 0.5));
			cur = [c.x, c.y];
		}
		else
			cur = resolveXY(e);
		if (t == -2)
		{
			e.target = -2;
			e.duration = 0;
		}
		else
		{
			if (wasRelease && e.duration <= 0)
				e.duration = Math.min(Math.max(0, songLen - e.time), kwLastDuration > 0 ? kwLastDuration : 500);
			if (t >= 0)
			{
				e.target = t;
				e.x = 0;
				e.y = 0;
			}
			else
			{
				e.target = -1;
				e.x = cur[0];
				e.y = cur[1];
			}
		}
		cameraEventCacheDirty = true;
		cameraEventListDirty = true;
		pauseHold = false;
		syncCameraEvents();
	}

	function setTarget(t:Int):Void
	{
		if (selected == null) return;
		var e = selected;
		var old = copyEv(e);
		applyTargetTo(e, t);
		commitProp(e, old);
	}

	function applyWarp(on:Bool):Void
	{
		if (selected == null || selected.track == 'general') return;
		var e = selected;
		var old = copyEv(e);
		if (on)
		{
			if (e.duration > 0) kwLastDuration = e.duration;
			e.duration = 0;
		}
		else
			e.duration = Math.min(Math.max(0, songLen - e.time), kwLastDuration > 0 ? kwLastDuration : 500);
		commitProp(e, old);
	}

	function doKeyAction(id:String):Void
	{
		if (selected == null) return;
		switch (id)
		{
			case 'warp':
				var on = selected.duration > 0;
				applyWarp(on);
				status(on ? 'Warp: กล้องกระโดดไปตำแหน่ง/ซูมใหม่ทันที (Duration = 0 ms)' : 'ปิด Warp: กล้องเลื่อนนุ่ม ๆ ตาม Ease');
			case 'release':
				var was = selected.target == -2;
				setTarget(was ? -1 : -2);
				status(was ? 'ยกเลิก Release: กลับมาเป็นโฟกัสตำแหน่งเอง (Custom)' : 'Release: ตั้งแต่จุดนี้ กล้องกลับไปตามปกติ (ตาม section ของเกม)');
			case 'autorelease':
				if (selected.track != 'focus' || selected.target == -2) return;
				var old = copyEv(selected);
				selected.autoRelease = selected.autoRelease != true;
				commitProp(selected, old);
				status(selected.autoRelease == true ? 'เปิด Auto-release: ปล่อยกล้องเมื่อ Duration จบ' : 'ปิด Auto-release: กล้องค้างจนถึง Release หรือ Focus ถัดไป');
			case 'resetzoom':
				setPropValue('zoom', defaultZoom);
				status('Reset zoom: ซูมกลับค่าปกติของฉาก (' + defaultZoom + ')');
			case 'resettilt':
				setPropValue('angle', 0);
				status('Reset tilt: กล้องกลับมาตรง (0 องศา)');
			default:
		}
	}

	function targetLabelOf(e:CamEvent):String
	{
		if (e.track == 'general') return whoName(Std.int(Math.max(0, Math.min(2, e.target))));
		if (e.target == -2) return 'Release (back to normal)';
		if (e.target >= 0 && e.target < 3) return TARGET_NAMES[e.target + 1];
		return 'Custom (X / Y)';
	}

	// ---------- ease name <-> (type, direction) ----------

	function splitEase(name:String):{base:String, dir:Int}
	{
		if (name == null || name == 'linear') return {base: 'linear', dir: 1};
		var dirIdx = -1;
		var base = name;
		if (camEndsWith(name, 'InOut'))
		{
			dirIdx = 2;
			base = name.substr(0, name.length - 5);
		}
		else if (camEndsWith(name, 'Out'))
		{
			dirIdx = 1;
			base = name.substr(0, name.length - 3);
		}
		else if (camEndsWith(name, 'In'))
		{
			dirIdx = 0;
			base = name.substr(0, name.length - 2);
		}
		if (dirIdx < 0 || EASE_BASES.indexOf(base) < 0) return {base: name, dir: -1}; // ชื่อ ease แปลก ๆ แสดงตามจริง
		return {base: base, dir: dirIdx};
	}

	function joinEase(base:String, dir:Int):String
		return base == 'linear' ? 'linear' : base + EASE_DIRS[Std.int(Math.max(0, Math.min(2, dir)))];

	function setEase(base:String, dir:Int):Void
	{
		if (selected == null || selected.track == 'general') return;
		var e = selected;
		var old = copyEv(e);
		e.ease = joinEase(base, dir);
		commitProp(e, old);
	}

	// ---------- drop-down popup ----------

	function openDropdown(ax:Float, ay:Float, aw:Float, ah:Float, options:Array<String>, current:Int, pick:Int->Void):Void
	{
		ddOptions = options;
		ddCurrent = current;
		ddPick = pick;
		ddX = ax;
		ddW = aw;
		var vis = Std.int(Math.min(options.length, 12));
		var h = vis * 24 + 8;
		ddY = ay + ah + 2;
		if (ddY + h > FlxG.height - 4) ddY = Math.max(4, ay - h - 2);
		ddScroll = Std.int(Math.max(0, Math.min(options.length - vis, current - 4)));
		ddOpen = true;
	}

	inline function ddVisible():Int
		return Std.int(Math.min(ddOptions.length, 12));

	function ddOverlaps(x:Float, y:Float, w:Float, h:Float):Bool
	{
		if (!ddOpen) return false;
		var dh = ddVisible() * 24 + 8;
		return x < ddX + ddW + 2 && x + w > ddX - 2 && y < ddY + dh + 2 && y + h > ddY - 2;
	}

	function openTargetDropdown(ax:Float, ay:Float, aw:Float, ah:Float):Void
	{
		if (selected == null) return;
		var labels:Array<String>;
		var values:Array<Int>;
		if (selected.track == 'general')
		{
			labels = ['BF', 'Opponent', 'GF'];
			values = [0, 1, 2];
		}
		else
		{
			labels = TARGET_LABELS;
			values = TARGET_ORDER;
		}
		openDropdown(ax, ay, aw, ah, labels, values.indexOf(selected.target), function(i:Int) setTarget(values[i]));
	}

	function openEaseBaseDropdown(ax:Float, ay:Float, aw:Float, ah:Float):Void
	{
		if (selected == null) return;
		var sp = splitEase(selected.ease);
		openDropdown(ax, ay, aw, ah, EASE_BASE_LABELS, EASE_BASES.indexOf(sp.base), function(i:Int)
		{
			if (selected == null) return;
			var cur = splitEase(selected.ease);
			setEase(EASE_BASES[i], cur.dir < 0 ? 1 : cur.dir);
		});
	}

	function openEaseDirDropdown(ax:Float, ay:Float, aw:Float, ah:Float):Void
	{
		if (selected == null) return;
		var sp = splitEase(selected.ease);
		if (sp.dir < 0 || sp.base == 'linear')
		{
			status(sp.base == 'linear' ? 'Linear ไม่มีทิศทาง In/Out' : 'เลือกชนิด Ease ก่อน');
			return;
		}
		openDropdown(ax, ay, aw, ah, EASE_DIR_LABELS, sp.dir, function(i:Int)
		{
			if (selected == null) return;
			setEase(splitEase(selected.ease).base, i);
		});
	}

	function handleDropdownMouse(mx:Float, my:Float):Bool
	{
		if (!ddOpen) return false;
		var vis = ddVisible();
		var inside = inRect(mx, my, ddX, ddY, ddW, vis * 24 + 8);
		if (FlxG.mouse.wheel != 0 && inside)
			ddScroll = Std.int(Math.max(0, Math.min(ddOptions.length - vis, ddScroll - FlxG.mouse.wheel)));
		if (FlxG.mouse.justPressed)
		{
			if (inside)
			{
				var row = Std.int((my - ddY - 4) / 24);
				var idx = ddScroll + row;
				if (row >= 0 && row < vis && idx >= 0 && idx < ddOptions.length)
				{
					var pick = ddPick;
					ddOpen = false;
					if (pick != null) pick(idx);
				}
			}
			else
				ddOpen = false;
		}
		return true; // popup เป็น modal: กลืนเมาส์ทั้งหมดระหว่างเปิด
	}

	function drawDropdown():Void
	{
		for (t in ddRows) t.visible = false;
		if (!ddOpen) return;
		var vis = ddVisible();
		var h = vis * 24 + 8;
		var mx = FlxG.mouse.gameX, my = FlxG.mouse.gameY;
		rect(ddX - 1, ddY - 1, ddW + 2, h + 2, 0xFF667383);
		rect(ddX, ddY, ddW, h, 0xFF1B1F25);
		for (i in 0...vis)
		{
			var idx = ddScroll + i;
			var ry = ddY + 4 + i * 24;
			if (idx == ddCurrent) rect(ddX + 3, ry, ddW - 6, 24, 0xFF35515C);
			else if (inRect(mx, my, ddX, ry, ddW, 24)) rect(ddX + 3, ry, ddW - 6, 24, 0xFF2E3640);
			var t = ddRows[i];
			setTextIfChanged(t, ddOptions[idx]);
			t.setPosition(ddX + 12, ry + 5);
			t.visible = true;
		}
		if (ddOptions.length > vis)
		{
			var th = Math.max(12, h * vis / ddOptions.length);
			rect(ddX + ddW - 5, ddY + (h - th) * ddScroll / (ddOptions.length - vis), 3, th, 0xFF6A7482);
		}
	}

	// ---------- key window open / close ----------

	function openKeyWindow():Void
	{
		if (!keyWindowSupported())
		{
			status('เลือก key (Focus / Zoom / Tilt / Add Camera Zoom / General) ก่อน แล้วดับเบิลคลิก / กด Enter / F2 เพื่อเปิดหน้าต่างแก้ไข');
			return;
		}
		kwOpen = true;
		kwAnimT = 0;
		ddOpen = false;
		if (selected.duration > 0) kwLastDuration = selected.duration;
		kwRefreshFrom();
	}

	function closeKeyWindow():Void
	{
		kwOpen = false;
		ddOpen = false;
		for (inp in kwInputs) hideInput(inp);
	}

	/** จำตำแหน่ง/ซูมของกล้อง "ก่อน" key นี้เริ่ม ใช้เป็นจุดเริ่มของตัวอย่างการขยับ */
	function kwRefreshFrom():Void
	{
		if (selected == null) return;
		var cam = evalAt(Math.max(0, selected.time - 0.5));
		kwFromX = cam.x;
		kwFromY = cam.y;
		kwFromZoom = Math.max(0.01, cam.zoom);
		kwFromAngle = evalAngleAt(Math.max(0, selected.time - 0.5));
		kwFromFor = selected;
		kwFromTime = selected.time;
	}

	function kwRows():Array<{key:String, label:String, y:Float}>
	{
		var out:Array<{key:String, label:String, y:Float}> = [];
		if (selected == null) return out;
		var y = kwY() + 48;
		var add = function(k:String, l:String)
		{
			out.push({key: k, label: l, y: y});
			y += 34;
		};
		switch (selected.track)
		{
			case 'focus':
				add('target', 'Target');
				if (selected.target != -2)
				{
					add('x', selected.target >= 0 ? 'Offset X' : 'X Position');
					add('y', selected.target >= 0 ? 'Offset Y' : 'Y Position');
					add('duration', 'Duration (ms)');
				}
				add('time', 'Time (ms)');
			case 'zoom':
				add('zoom', 'Zoom');
				add('duration', 'Duration (ms)');
				add('time', 'Time (ms)');
			case 'tilt':
				add('angle', 'Angle (deg)');
				add('duration', 'Duration (ms)');
				add('time', 'Time (ms)');
			case 'kick':
				add('zoom', 'Zoom amount');
				add('time', 'Time (ms)');
			case 'general':
				add('target', 'Target');
				add('time', 'Time (ms)');
			default:
		}
		return out;
	}

	function kwButtonRects():Array<KwButton>
	{
		var out:Array<KwButton> = [];
		if (selected == null || selected.track == 'general' || selected.track == 'kick') return out;
		var rows = kwRows();
		var y = rows.length > 0 ? rows[rows.length - 1].y + 38 : kwY() + 48;
		var x = kwX() + 14;
		var warpOn = selected.duration <= 0;
		if (selected.track == 'focus')
		{
			if (selected.target != -2)
				out.push({id: 'warp', label: warpOn ? 'Warp: ON (instant cut)' : 'Warp (instant cut)', x: x, y: y, w: 146, h: 26, active: warpOn});
			out.push({
				id: 'release',
				label: selected.target == -2 ? 'Released  (click = undo)' : 'Release to normal',
				x: selected.target == -2 ? x : x + 154,
				y: y,
				w: selected.target == -2 ? 300 : 146,
				h: 26,
				active: selected.target == -2
			});
		}
		else
		{
			out.push({id: 'warp', label: warpOn ? 'Warp: ON (instant cut)' : 'Warp (instant cut)', x: x, y: y, w: 146, h: 26, active: warpOn});
			out.push({id: selected.track == 'tilt' ? 'resettilt' : 'resetzoom', label: selected.track == 'tilt' ? 'Reset tilt (0 deg)' : 'Reset zoom (normal)', x: x + 154, y: y, w: 146, h: 26, active: false});
		}
		return out;
	}

	function handleKeyWindowMouse(mx:Float, my:Float):Bool
	{
		if (!kwOpen) return false;
		var wx = kwX(), wy = kwY();
		var inside = inRect(mx, my, wx, wy, KW_W, KW_H);
		var mult:Float = FlxG.keys.pressed.SHIFT ? 5 : (FlxG.keys.pressed.ALT ? 0.1 : 1);
		if (!inside)
		{
			// คลิกนอกหน้าต่าง (และไม่ใช่แผงขวา/แถบเมนู) = ปิดหน้าต่าง แล้วให้คลิกนั้นทำงานต่อตามปกติ
			if (FlxG.mouse.justPressed && mx < PANEL_X && my >= 32) closeKeyWindow();
			return false;
		}
		var fx = wx + 112;
		var rows = kwRows();
		if (FlxG.mouse.wheel != 0)
		{
			for (r in rows)
				if (r.key != 'target' && inRect(mx, my, wx + 14, r.y, 300, 26))
				{
					adjustProp(r.key, FlxG.mouse.wheel > 0 ? 1 : -1, mult);
					break;
				}
		}
		if (!FlxG.mouse.justPressed) return true;
		if (inRect(mx, my, wx + KW_W - 74, wy + 5, 62, 26))
		{
			closeKeyWindow();
			return true;
		}
		for (r in rows)
		{
			if (!inRect(mx, my, fx, r.y, KW_FW, 26)) continue;
			if (r.key == 'target') openTargetDropdown(fx, r.y, KW_FW, 26);
			else if (mx < fx + 24) adjustProp(r.key, -1, mult);
			else if (mx >= fx + KW_FW - 24) adjustProp(r.key, 1, mult);
			return true;
		}
		for (b in kwButtonRects())
			if (inRect(mx, my, b.x, b.y, b.w, b.h))
			{
				doKeyAction(b.id);
				return true;
			}
		if (showEaseSection())
		{
			if (inRect(mx, my, wx + 14, wy + 286, 150, 26))
			{
				openEaseBaseDropdown(wx + 14, wy + 286, 150, 26);
				return true;
			}
			if (inRect(mx, my, wx + 14, wy + 320, 150, 26))
			{
				openEaseDirDropdown(wx + 14, wy + 320, 150, 26);
				return true;
			}
			if (selected != null && selected.track == 'focus' && selected.target != -2 && inRect(mx, my, wx + 14, wy + 350, 300, 24))
			{
				doKeyAction('autorelease');
				return true;
			}
		}
		return true;
	}

	// ---------- animated preview helpers ----------

	/** ความคืบหน้าแบบเส้นตรง 0..1 ของอนิเมชันตัวอย่าง (วนซ้ำ: หยุดต้น -> เคลื่อน -> หยุดปลาย) */
	function kwLin():Float
	{
		var dur = selected != null ? selected.duration / 1000 : 0.5;
		var vd = dur <= 0 ? 0.0 : Math.max(0.4, Math.min(3.0, dur));
		var lead = 0.35;
		var cycle = lead + vd + 0.65;
		var t = kwAnimT % cycle;
		if (vd <= 0) return t >= lead ? 1 : 0; // Warp: โดดทีเดียว
		return Math.max(0, Math.min(1, (t - lead) / vd));
	}

	function kwEaseAt(lin:Float):Float
	{
		if (selected == null || selected.duration <= 0) return lin;
		return easeFn(selected.ease)(lin);
	}

	function easeRange(f:Float->Float, n:Int):Array<Float>
	{
		var lo:Float = 0, hi:Float = 1;
		for (i in 0...(n + 1))
		{
			var v = f(i / n);
			if (v < lo) lo = v;
			if (v > hi) hi = v;
		}
		var pad = (hi - lo) * 0.08;
		return [lo - pad, hi + pad];
	}

	function clipRect(x:Float, y:Float, w:Float, h:Float, c:FlxColor, bx:Float, by:Float, bw:Float, bh:Float):Void
	{
		var x1 = Math.max(x, bx), y1 = Math.max(y, by);
		var x2 = Math.min(x + w, bx + bw), y2 = Math.min(y + h, by + bh);
		if (x2 > x1 && y2 > y1) rect(x1, y1, x2 - x1, y2 - y1, c);
	}

	function clipFrame(x:Float, y:Float, w:Float, h:Float, c:FlxColor, t:Float, bx:Float, by:Float, bw:Float, bh:Float):Void
	{
		clipRect(x, y, w, t, c, bx, by, bw, bh);
		clipRect(x, y + h - t, w, t, c, bx, by, bw, bh);
		clipRect(x, y, t, h, c, bx, by, bw, bh);
		clipRect(x + w - t, y, t, h, c, bx, by, bw, bh);
	}

	/** กราฟ Ease เหมือนในภาพตัวอย่าง: เส้น 0 และ 1 เป็นเส้นเทา เส้นขาวคือโค้ง จุดเหลืองคือตำแหน่งปัจจุบันของอนิเมชัน */
	function drawEaseCurve(x:Float, y:Float, w:Float, h:Float, easeName:String, progress:Float, showDot:Bool):Void
	{
		var f = easeFn(easeName);
		var n = Std.int(Math.max(8, Math.floor(w / 2)));
		var range = easeRange(f, n);
		var lo = range[0];
		var span = range[1] - range[0];
		rect(x, y, w, h, 0xFF1F2227);
		rect(x, y + h - (0 - lo) / span * h, w, 1, 0xFF4A5059);
		rect(x, y + h - (1 - lo) / span * h, w, 1, 0xFF4A5059);
		var prev = f(0);
		for (i in 1...(n + 1))
		{
			var cur = f(i / n);
			var py1 = y + h - (prev - lo) / span * h;
			var py2 = y + h - (cur - lo) / span * h;
			clipRect(x + (i - 1) / n * (w - 2), Math.min(py1, py2), 2, Math.max(2, Math.abs(py2 - py1) + 1), 0xFFFFFFFF, x, y, w, h);
			prev = cur;
		}
		if (showDot)
		{
			var dx = x + progress * (w - 2);
			var dy = y + h - (f(progress) - lo) / span * h;
			rect(dx, y, 1, h, 0xFF6A5B2E);
			clipRect(dx - 3, dy - 3, 6, 6, 0xFFFFD16C, x, y, w, h);
		}
	}

	/** แถบตั้งข้างกราฟ: จุดขึ้น/ลงตามค่า ease (ช่วง overshoot ของ Elastic/Back จะเห็นจุดเลยเส้นบนหรือล่าง) */
	function drawEaseDotBar(x:Float, y:Float, w:Float, h:Float, easeName:String, progress:Float):Void
	{
		var f = easeFn(easeName);
		var n = Std.int(Math.max(8, Math.floor(w)));
		var range = easeRange(f, 100);
		var lo = range[0];
		var span = range[1] - range[0];
		rect(x, y, w, h, 0xFF1F2227);
		rect(x, y + h - (0 - lo) / span * h, w, 1, 0xFF4A5059);
		rect(x, y + h - (1 - lo) / span * h, w, 1, 0xFF4A5059);
		var dy = y + h - (f(progress) - lo) / span * h;
		clipRect(x + w * 0.5 - 4, dy - 4, 8, 8, 0xFFFFFFFF, x, y, w, h);
	}

	/** ตัวอย่างการขยับของ Focus: แผนที่ย่อ กรอบกล้องเริ่ม (เทา) -> กรอบปลายทาง (ฟ้า) กรอบเหลืองคือกล้องที่กำลังวิ่งตาม Ease */
	function drawFocusMotion(bx:Float, by:Float, bw:Float, bh:Float, e:CamEvent, eased:Float):Void
	{
		var lens = cameraLensSize();
		var z = Math.max(0.01, kwFromZoom);
		var fw = lens.width / z;
		var fh = lens.height / z;
		var ax = kwFromX, ay = kwFromY;
		var tx = resolveX(e), ty = resolveY(e);
		var left = Math.min(ax, tx) - fw * 0.5, right = Math.max(ax, tx) + fw * 0.5;
		var top = Math.min(ay, ty) - fh * 0.5, bottom = Math.max(ay, ty) + fh * 0.5;
		for (i in 0...charPos.length)
		{
			left = Math.min(left, charPos[i][0] - 30);
			right = Math.max(right, charPos[i][0] + 30);
			top = Math.min(top, charPos[i][1] - 30);
			bottom = Math.max(bottom, charPos[i][1] + 30);
		}
		var s = Math.min((bw - 20) / Math.max(1, right - left), (bh - 20) / Math.max(1, bottom - top));
		var ox = bx + bw * 0.5 - (left + right) * 0.5 * s;
		var oy = by + bh * 0.5 - (top + bottom) * 0.5 * s;
		rect(bx, by, bw, bh, 0xFF1F2227);
		for (i in 0...charPos.length)
			clipRect(ox + charPos[i][0] * s - 3, oy + charPos[i][1] * s - 3, 6, 6, whoColor(i), bx, by, bw, bh);
		clipFrame(ox + (ax - fw * 0.5) * s, oy + (ay - fh * 0.5) * s, fw * s, fh * s, 0xFF6A7482, 1, bx, by, bw, bh);
		clipFrame(ox + (tx - fw * 0.5) * s, oy + (ty - fh * 0.5) * s, fw * s, fh * s, 0xFF5AA9FF, 1, bx, by, bw, bh);
		for (i in 0...13)
		{
			var q = i / 12;
			clipRect(ox + (ax + (tx - ax) * q) * s - 1, oy + (ay + (ty - ay) * q) * s - 1, 2, 2, 0xFF8892A0, bx, by, bw, bh);
		}
		var cx = ax + (tx - ax) * eased;
		var cy = ay + (ty - ay) * eased;
		clipFrame(ox + (cx - fw * 0.5) * s, oy + (cy - fh * 0.5) * s, fw * s, fh * s, 0xFFFFD16C, 2, bx, by, bw, bh);
		clipRect(ox + cx * s - 2, oy + cy * s - 2, 4, 4, 0xFFFFD16C, bx, by, bw, bh);
	}

	/** ตัวอย่างการซูม: กรอบซ้อนกันที่กึ่งกลาง เทา = ซูมเริ่ม ฟ้า = ซูมปลายทาง เหลือง = ซูมที่กำลังวิ่งตาม Ease */
	function drawZoomMotion(bx:Float, by:Float, bw:Float, bh:Float, e:CamEvent, eased:Float):Void
	{
		var lens = cameraLensSize();
		var lw = lens.width, lh = lens.height;
		var z0 = Math.max(0.01, kwFromZoom), z1 = Math.max(0.01, e.zoom);
		var zmin = Math.min(z0, z1);
		var s = Math.min((bw - 20) / (lw / zmin), (bh - 20) / (lh / zmin));
		var cx = bx + bw * 0.5, cy = by + bh * 0.5;
		var zc = Math.max(0.01, Math.min(8, z0 + (z1 - z0) * eased));
		rect(bx, by, bw, bh, 0xFF1F2227);
		clipFrame(cx - lw / z0 * s * 0.5, cy - lh / z0 * s * 0.5, lw / z0 * s, lh / z0 * s, 0xFF6A7482, 1, bx, by, bw, bh);
		clipFrame(cx - lw / z1 * s * 0.5, cy - lh / z1 * s * 0.5, lw / z1 * s, lh / z1 * s, 0xFF5AA9FF, 1, bx, by, bw, bh);
		clipFrame(cx - lw / zc * s * 0.5, cy - lh / zc * s * 0.5, lw / zc * s, lh / zc * s, 0xFFFFD16C, 2, bx, by, bw, bh);
	}

	/** ตัวอย่างการเอียง: กรอบกล้องหมุนรอบกึ่งกลาง เทา = มุมเริ่ม ฟ้า = มุมปลายทาง เหลือง = มุมที่กำลังวิ่งตาม Ease */
	function drawTiltMotion(bx:Float, by:Float, bw:Float, bh:Float, e:CamEvent, eased:Float):Void
	{
		var lens = cameraLensSize();
		var diag = Math.sqrt(lens.width * lens.width + lens.height * lens.height);
		var s = Math.min(bw - 16, bh - 16) / Math.max(1, diag);
		var cx = bx + bw * 0.5, cy = by + bh * 0.5;
		var a0 = kwFromAngle, a1 = angleOf(e);
		var ac = a0 + (a1 - a0) * eased;
		rect(bx, by, bw, bh, 0xFF1F2227);
		tiltFrame(cx, cy, lens.width * s, lens.height * s, a0, 0xFF6A7482, 1, bx, by, bw, bh);
		tiltFrame(cx, cy, lens.width * s, lens.height * s, a1, 0xFF5AA9FF, 1, bx, by, bw, bh);
		tiltFrame(cx, cy, lens.width * s, lens.height * s, ac, 0xFFFFD16C, 2, bx, by, bw, bh);
		clipRect(cx - 3, cy, 7, 1, 0xFF8892A0, bx, by, bw, bh);
		clipRect(cx, cy - 3, 1, 7, 0xFF8892A0, bx, by, bw, bh);
	}

	/** กรอบสี่เหลี่ยมที่หมุน deg องศา (ตามเข็ม) รอบ (cx, cy) วาดเป็นจุดต่อกันและตัดให้อยู่ในกล่อง bx..bh */
	function tiltFrame(cx:Float, cy:Float, w:Float, h:Float, deg:Float, c:FlxColor, t:Float, bx:Float, by:Float, bw:Float, bh:Float):Void
	{
		var rad = deg * Math.PI / 180;
		var cs = Math.cos(rad), sn = Math.sin(rad);
		var hw = w * 0.5, hh = h * 0.5;
		var xs:Array<Float> = [], ys:Array<Float> = [];
		for (p in [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]])
		{
			xs.push(cx + p[0] * cs - p[1] * sn);
			ys.push(cy + p[0] * sn + p[1] * cs);
		}
		for (i in 0...4)
		{
			var j = (i + 1) % 4;
			var len = Math.sqrt((xs[j] - xs[i]) * (xs[j] - xs[i]) + (ys[j] - ys[i]) * (ys[j] - ys[i]));
			var steps = Std.int(Math.max(1, Math.min(600, Math.ceil(len / t))));
			for (k in 0...(steps + 1))
			{
				var q = k / steps;
				clipRect(xs[i] + (xs[j] - xs[i]) * q - t * 0.5, ys[i] + (ys[j] - ys[i]) * q - t * 0.5, t, t, c, bx, by, bw, bh);
			}
		}
	}

	function kwText(s:String, x:Float, y:Float, color:FlxColor = 0xFFE3E8EF):Void
	{
		if (kwTextUsed >= kwTexts.length) return;
		var t = kwTexts[kwTextUsed++];
		setTextIfChanged(t, s);
		t.color = th(color);
		t.setPosition(x, y);
		t.visible = !ddOverlaps(x, y, s.length * 7, 16);
	}

	function kwDropButton(x:Float, y:Float, w:Float, label:String, enabled:Bool):Void
	{
		var hov = inRect(FlxG.mouse.gameX, FlxG.mouse.gameY, x, y, w, 26);
		rect(x, y, w, 26, enabled && hov ? 0xFF3A4452 : 0xFF1B1F25);
		frameRect(x, y, w, 26, 0xFF3A4452, 1);
		kwText(label, x + 10, y + 6, enabled ? 0xFFFFFFFF : 0xFF7C8794);
		if (enabled) kwText('v', x + w - 18, y + 6, 0xFF9FB3C8);
	}

	function drawKeyWindow():Void
	{
		kwTextUsed = 0;
		if (kwOpen && (!keyWindowSupported() || activeMenu != null || helpOpen || eventPickerOpen)) closeKeyWindow();
		if (!kwOpen)
		{
			for (t in kwTexts) t.visible = false;
			for (inp in kwInputs) hideInput(inp);
			drawDropdown();
			return;
		}
		var e = selected;
		var wx = kwX(), wy = kwY();
		var mx = FlxG.mouse.gameX, my = FlxG.mouse.gameY;
		if (kwFromFor != e || kwFromTime != e.time) kwRefreshFrom();
		if (vcamInfoText != null) vcamInfoText.visible = false;

		rect(wx, wy, KW_W, KW_H, 0xFF252A32);
		frameRect(wx, wy, KW_W, KW_H, 0xFF667383, 2);
		rect(wx + 2, wy + 2, KW_W - 4, 34, 0xFF303742);
		rect(wx + 2, wy + 36, KW_W - 4, 1, 0xFF48515D);
		var title = e.track == 'focus' ? (e.target == -2 ? 'Focus Camera  -  Release' : 'Focus Camera') : (e.track == 'zoom' ? 'Zoom Camera' : (e.track == 'tilt' ? 'Tilt Camera' : 'General Camera'));
		kwText(title, wx + 14, wy + 10, 0xFFEDF1F6);
		var hideHov = inRect(mx, my, wx + KW_W - 74, wy + 5, 62, 26);
		rect(wx + KW_W - 74, wy + 5, 62, 26, hideHov ? 0xFF4A5462 : 0xFF3A4452);
		frameRect(wx + KW_W - 74, wy + 5, 62, 26, 0xFF596676, 1);
		kwText('Hide', wx + KW_W - 56, wy + 10, 0xFFFFFFFF);

		// ---- ช่องค่า (พิมพ์ตัวเลขเองได้ / กด < > / ล้อเมาส์) ----
		var fx = wx + 112;
		var used:Array<String> = [];
		for (r in kwRows())
		{
			kwText(r.label, wx + 14, r.y + 6, 0xFFC9D2DD);
			if (r.key == 'target')
			{
				kwDropButton(fx, r.y, KW_FW, targetLabelOf(e), true);
				continue;
			}
			rect(fx, r.y, KW_FW, 26, 0xFF1B1F25);
			frameRect(fx, r.y, KW_FW, 26, 0xFF3A4452, 1);
			kwText('<', fx + 9, r.y + 5, 0xFF5AA9FF);
			kwText('>', fx + KW_FW - 16, r.y + 5, 0xFF5AA9FF);
			var inp = kwInputs.get(r.key);
			if (inp == null) continue;
			if (ddOverlaps(fx, r.y, KW_FW, 26))
			{
				hideInput(inp);
				continue;
			}
			showInput(inp, fx + 26, r.y + 3);
			syncNumInput(inp, r.key);
			used.push(r.key);
		}
		for (k => inp in kwInputs)
			if (used.indexOf(k) < 0) hideInput(inp);

		// ---- ปุ่ม Warp / Release / Reset zoom ----
		for (b in kwButtonRects())
		{
			var hov = inRect(mx, my, b.x, b.y, b.w, b.h);
			rect(b.x, b.y, b.w, b.h, b.active ? 0xFF35515C : (hov ? 0xFF3A4452 : 0xFF2E353F));
			frameRect(b.x, b.y, b.w, b.h, b.active ? 0xFFFFD16C : 0xFF48515D, 1);
			kwText(b.label, b.x + 10, b.y + 6, 0xFFFFFFFF);
		}

		var rx = wx + 330;
		if (showEaseSection())
		{
			// ---- Ease controls on the left, clean curve preview on the right ----
			var ey = wy + 262;
			rect(wx + 14, ey - 6, 300, 1, 0xFF48515D);
			kwText('Ease', wx + 14, ey, 0xFFEDF1F6);
			var sp = splitEase(e.ease);
			var baseIndex = EASE_BASES.indexOf(sp.base);
			var baseLabel = sp.dir >= 0 && baseIndex >= 0 ? EASE_BASE_LABELS[baseIndex] : e.ease;
			var dirLabel = sp.dir >= 0 && sp.base != 'linear' ? EASE_DIR_LABELS[sp.dir] : '-';
			kwDropButton(wx + 14, wy + 286, 150, baseLabel, true);
			kwDropButton(wx + 14, wy + 320, 150, dirLabel, sp.dir >= 0 && sp.base != 'linear');
			kwText(e.ease, wx + 176, wy + 292, 0xFF8892A0);
			if (e.track == 'focus' && e.target != -2)
			{
				var arX = wx + 14, arY = wy + 354;
				var arOn = e.autoRelease == true;
				var arHover = inRect(mx, my, arX, arY, 300, 20);
				rect(arX, arY, 16, 16, arOn ? 0xFF284E3E : 0xFF1B1F25);
				frameRect(arX, arY, 16, 16, arOn ? 0xFF65D6A2 : (arHover ? 0xFF8AA0B7 : 0xFF596676), 1);
				if (arOn) kwText('✓', arX + 3, arY + 1, 0xFF8AF0B9);
				kwText('Auto-release when Duration ends', arX + 23, arY + 1, arOn ? 0xFF8AF0B9 : 0xFFC9D2DD);
			}

			// แสดงกราฟ Ease อย่างเดียวเหมือนแผงแก้ไขมาตรฐาน ลดข้อมูลตัวอย่างที่ทำให้ UI แน่นเกินไป
			var lin = kwLin();
			var pe = kwEaseAt(lin);
			kwText('Ease curve', rx, wy + 44, 0xFFC9D2DD);
			kwText(e.duration <= 0 ? 'WARP / INSTANT' : Math.round(e.duration) + ' ms', rx + 118, wy + 44, e.duration <= 0 ? 0xFFFFD16C : 0xFF8892A0);
			drawEaseCurve(rx, wy + 66, 220, 130, e.ease, lin, e.duration > 0);
			drawEaseDotBar(rx + 232, wy + 66, 54, 130, e.ease, pe);
			// label column is 84px wide so "Eased value" no longer runs into the yellow bar
			kwText('Progress', rx, wy + 204, 0xFF8892A0);
			rect(rx + 90, wy + 209, 196, 8, 0xFF1B1F25);
			rect(rx + 90, wy + 209, 196 * lin, 8, 0xFF5AA9FF);
			kwText('Eased value', rx, wy + 222, 0xFF8892A0);
			rect(rx + 90, wy + 227, 196, 8, 0xFF1B1F25);
			rect(rx + 90, wy + 227, 196 * Math.max(0, Math.min(1, pe)), 8, 0xFFFFD16C);

			// ---- Motion preview: shows how the camera moves / zooms / tilts with this key's values ----
			var mTitle = e.track == 'focus' ? 'Motion preview - camera move' : (e.track == 'zoom' ? 'Motion preview - zoom' : 'Motion preview - tilt');
			kwText(mTitle, rx, wy + 248, 0xFFC9D2DD);
			var mbx = rx, mby = wy + 268, mbw = 286.0, mbh = 118.0;
			if (e.track == 'focus') drawFocusMotion(mbx, mby, mbw, mbh, e, pe);
			else if (e.track == 'zoom') drawZoomMotion(mbx, mby, mbw, mbh, e, pe);
			else drawTiltMotion(mbx, mby, mbw, mbh, e, pe);
			frameRect(mbx, mby, mbw, mbh, 0xFF3A4452, 1);
			kwText('grey = start   blue = end   yellow = now', rx, wy + 392, 0xFF8892A0);
		}
		else if (e.track == 'focus')
		{
			kwText('RELEASE', rx, wy + 52, 0xFFFFD16C);
			kwText('From this time on the camera is no longer forced.\nIt goes back to normal: following the character\nof the current section, like the game does.\n\nClick "Released" to turn it back into a normal\nfocus key (Custom X / Y).', rx, wy + 76, 0xFFC9D2DD);
		}
		else
		{
			kwText('GENERAL CAMERA', rx, wy + 52, 0xFFFFD16C);
			kwText('The camera looks at the chosen character\n(BF / Opponent / GF) from this time on.\n\nPick the character from the Target drop-down.', rx, wy + 76, 0xFFC9D2DD);
		}
		// two short lines: the old single line was wider than the window and spilled onto the yellow background
		kwText('Enter / F2 / double-click a key = open    Esc = close', wx + 14, wy + KW_H - 40, 0xFF7C8794);
		kwText('Type a value or use the arrows / wheel  (Shift = x5, Alt = x0.1; zoom step 0.01)', wx + 14, wy + KW_H - 24, 0xFF7C8794);
		for (k in kwTextUsed...kwTexts.length) kwTexts[k].visible = false;
		drawDropdown();
	}

	// ---------- แผงขวา: ปุ่มลัด + ตัวอย่าง Ease ย่อ ----------

	function panelExtraLayout():{buttons:Array<KwButton>, prevY:Float, prevH:Float}
	{
		if (selected == null || selected.track == 'general') return null;
		var rows = propLayout();
		if (rows.length == 0) return null;
		var last = rows[rows.length - 1];
		var y = last.y + last.h + 4;
		if (y + 24 > PREV_Y + previewPanelHeight() - 6) return null;
		var bw = (PANEL_W - 28 - 6) / 2;
		var x = PANEL_X + 14;
		var warpOn = selected.duration <= 0;
		var buttons:Array<KwButton> = [];
		if (selected.track == 'focus')
		{
			if (selected.target != -2)
				buttons.push({id: 'warp', label: warpOn ? 'Warp: ON' : 'Warp (cut)', x: x, y: y, w: bw, h: 22, active: warpOn});
			buttons.push({
				id: 'release',
				label: selected.target == -2 ? 'Released' : 'Release',
				x: selected.target == -2 ? x : x + bw + 6,
				y: y,
				w: selected.target == -2 ? PANEL_W - 28 : bw,
				h: 22,
				active: selected.target == -2
			});
		}
		else
		{
			buttons.push({id: 'warp', label: warpOn ? 'Warp: ON' : 'Warp (cut)', x: x, y: y, w: bw, h: 22, active: warpOn});
			buttons.push({id: selected.track == 'tilt' ? 'resettilt' : 'resetzoom', label: selected.track == 'tilt' ? 'Reset tilt' : 'Reset zoom', x: x + bw + 6, y: y, w: bw, h: 22, active: false});
		}
		var prevY = y + 28;
		var prevH = PREV_Y + previewPanelHeight() - 6 - prevY;
		if (prevH < 30 || (selected.track == 'focus' && selected.target == -2)) prevH = 0;
		return {buttons: buttons, prevY: prevY, prevH: Math.min(prevH, 70)};
	}

	function drawPanelEasePreview(x:Float, y:Float, w:Float, h:Float):Void
	{
		var e = selected;
		var lin = kwLin();
		var pe = kwEaseAt(lin);
		drawEaseCurve(x, y, 96, h, e.ease, lin, e.duration > 0);
		var bx = x + 104;
		var bw = w - 104;
		rect(bx, y, bw, h, 0xFF1F2227);
		var x0 = bx + 12, x1 = bx + bw - 12;
		var cy = y + h * 0.5;
		rect(x0, cy - 1, x1 - x0, 2, 0xFF48515D);
		rect(x0 - 1, y + 4, 2, h - 8, 0xFF8892A0);
		rect(x1 - 1, y + 4, 2, h - 8, 0xFF5AA9FF);
		var dx = x0 + (x1 - x0) * pe;
		clipRect(Math.min(x0, dx), cy - 2, Math.abs(dx - x0), 4, 0xFF8A7440, bx, y, bw, h);
		clipRect(dx - 5, cy - 5, 10, 10, 0xFFFFD16C, bx, y, bw, h);
	}

	function handlePropertiesMouse(mx:Float, my:Float):Void
	{
		if (mx < PANEL_X || mx >= PANEL_X + PANEL_W) return;
		if (FlxG.mouse.justPressed && mode == None && keyWindowSupported() && inRect(mx, my, PANEL_X + PANEL_W - 76, PREV_Y + 5, 64, 24))
		{
			if (kwOpen) closeKeyWindow();
			else openKeyWindow();
			return;
		}
		var mult:Float = FlxG.keys.pressed.SHIFT ? 5 : (FlxG.keys.pressed.ALT ? 0.1 : 1);
		if (FlxG.mouse.justPressed && mode == None)
		{
			var ex = ddOpen ? null : panelExtraLayout();
			if (ex != null)
				for (b in ex.buttons)
					if (inRect(mx, my, b.x, b.y, b.w, b.h))
					{
						doKeyAction(b.id);
						return;
					}
		}
		for (r in propLayout())
		{
			if (my < r.y || my >= r.y + r.h) continue;
			var wheel = FlxG.mouse.wheel;
			var isSlider = r.key == 'zoomslider' || r.key == 'tiltslider';
			var key = r.key == 'tiltslider' ? 'angle' : (isSlider ? 'zoom' : r.key);
			if (wheel != 0) adjustProp(key, wheel > 0 ? 1 : -1, mult);
			if (FlxG.mouse.justPressed && mode == None)
			{
				if (isSlider)
				{
					mode = PropSlide;
					setPropSliderFromMouse(mx);
				}
				else
				{
					var bx = PANEL_X + PROP_BOX_X;
					var bw = PANEL_W - PROP_BOX_X - 12;
					if (mx >= bx && mx < bx + 26) adjustProp(key, -1, mult);
					else if (mx >= bx + bw - 26 && mx < bx + bw) adjustProp(key, 1, mult);
					else if (key == 'target') openTargetDropdown(bx, r.y + 2, bw, r.h - 4);
					else if (key == 'ease') openKeyWindow(); // เลือก Ease ในหน้าต่าง (มีกราฟตัวอย่าง)
				}
			}
			return;
		}
	}

	function drawPropertiesPanel():Void
	{
		kwAnimT += FlxG.elapsed;
		var rows = propLayout();
		var mx = FlxG.mouse.gameX, my = FlxG.mouse.gameY;
		var pi = 0;
		var usedInputs:Array<String> = [];
		for (r in rows)
		{
			if (pi >= propLabels.length) break;
			if (r.key == 'zoomslider' || r.key == 'tiltslider')
			{
				var sx = PANEL_X + 14;
				var sw = PANEL_W - 28;
				var cy = r.y + r.h * 0.5;
				rect(sx, cy - 2, sw, 4, 0xFF48515D);
				var tiltSlider = r.key == 'tiltslider';
				for (tick in (tiltSlider ? [-90.0, 0.0, 90.0] : [0.1, 0.2, 0.5, 1.0, 2.0, 3.0, 5.0]))
				{
					var tickPos = tiltSlider ? (tick + 180) / 360 : Math.sqrt(Math.max(0, (tick - 0.01) / 4.99));
					rect(sx + tickPos * sw, cy - 6, 1, 12, 0xFF71869B);
				}
				var hz = tiltSlider ? Math.max(0, Math.min(1, (angleOf(selected) + 180) / 360)) : Math.sqrt(Math.max(0, Math.min(1, (selected.zoom - 0.01) / 4.99)));
			rect(sx, cy - 2, hz * sw, 4, tiltSlider ? 0xFF5D9FC2 : 0xFF45B8C8);
			rect(sx + hz * sw - 6, cy - 9, 12, 18, mode == PropSlide ? 0xFFFFD16C : 0xFFE5F1F6);
				frameRect(sx + hz * sw - 6, cy - 9, 12, 18, 0xFF314B60, 1);
				propLabels[pi].visible = false;
				propValues[pi].visible = false;
				propArrows[pi * 2].visible = false;
				propArrows[pi * 2 + 1].visible = false;
				pi++;
				continue;
			}
			var bx = PANEL_X + PROP_BOX_X;
			var bw = PANEL_W - PROP_BOX_X - 12;
			var hover = inRect(mx, my, PANEL_X, r.y, PANEL_W, r.h);
			rect(PANEL_X + 8, r.y + 1, PANEL_W - 16, r.h - 2, hover ? 0xFF202D3A : 0xFF1B2530);
			rect(bx, r.y + 3, bw, r.h - 6, 0xFF111923);
			frameRect(bx, r.y + 3, bw, r.h - 6, 0xFF34495D, 1);
			var lt = propLabels[pi];
			setTextIfChanged(lt, r.label);
			lt.setPosition(PANEL_X + 14, r.y + (r.h - lt.height) * 0.5);
			lt.visible = true;
			var vt = propValues[pi];
			setTextIfChanged(vt, propValueText(r.key));
			vt.setPosition(bx + (bw - vt.width) * 0.5, r.y + (r.h - vt.height) * 0.5);
			vt.visible = true;
			var al = propArrows[pi * 2];
			var ar = propArrows[pi * 2 + 1];
			var leftArrowHover = inRect(mx, my, bx, r.y + 3, 26, r.h - 6);
			var rightArrowHover = inRect(mx, my, bx + bw - 26, r.y + 3, 26, r.h - 6);
			rect(bx + 2, r.y + 5, 22, r.h - 10, leftArrowHover ? 0xFF2D4858 : 0xFF1C2B39);
			rect(bx + bw - 24, r.y + 5, 22, r.h - 10, rightArrowHover ? 0xFF2D4858 : 0xFF1C2B39);
			al.setPosition(bx + (26 - al.width) * 0.5, r.y + (r.h - al.height) * 0.5);
			ar.setPosition(bx + bw - 26 + (26 - ar.width) * 0.5, r.y + (r.h - ar.height) * 0.5);
			var inputFocused = panelInputs.get(r.key) != null && PsychUIInputText.focusOn == panelInputs.get(r.key);
			if (inputFocused) frameRect(bx, r.y + 3, bw, r.h - 6, 0xFF55C4D4, 1);
			al.color = ar.color = th(hover ? 0xFFBCEBF0 : 0xFF89A6B8);
			al.visible = ar.visible = true;
			// ช่องตัวเลข: พิมพ์ค่าเองได้ (ซ่อนตัวเลขข้อความเดิมของแถวนั้น)
			var inp = panelInputs.get(r.key);
			if (inp != null)
			{
				if (ddOverlaps(PANEL_X, r.y, PANEL_W, r.h)) hideInput(inp);
				else
				{
					showInput(inp, bx + 28, r.y + 6);
					syncNumInput(inp, r.key);
					vt.visible = false;
					usedInputs.push(r.key);
				}
			}
			if (ddOverlaps(PANEL_X, r.y, PANEL_W, r.h)) lt.visible = vt.visible = al.visible = ar.visible = false;
			pi++;
		}
		for (k => inp in panelInputs)
			if (usedInputs.indexOf(k) < 0) hideInput(inp);
		for (k in pi...propLabels.length)
		{
			propLabels[k].visible = false;
			propValues[k].visible = false;
			propArrows[k * 2].visible = false;
			propArrows[k * 2 + 1].visible = false;
		}

		// ปุ่ม Edit... ที่หัวแผง
		var showEdit = keyWindowSupported();
		editBtnText.visible = showEdit;
		if (showEdit)
		{
			var ex0 = PANEL_X + PANEL_W - 76;
			rect(ex0, PREV_Y + 5, 64, 24, kwOpen ? 0xFF35515C : (inRect(mx, my, ex0, PREV_Y + 5, 64, 24) ? 0xFF4A5462 : 0xFF3A4452));
			frameRect(ex0, PREV_Y + 5, 64, 24, 0xFF596676, 1);
			editBtnText.setPosition(ex0 + 10, PREV_Y + 9);
		}

		// ปุ่ม Warp / Release / Reset zoom + กราฟ Ease ย่อ + แถบจุดขยับ
		for (b in panelBtnTexts) b.visible = false;
		var ex = ddOpen ? null : panelExtraLayout();
		if (ex != null)
		{
			for (i in 0...ex.buttons.length)
			{
				var b = ex.buttons[i];
				var hov = inRect(mx, my, b.x, b.y, b.w, b.h);
				rect(b.x, b.y, b.w, b.h, b.active ? 0xFF35515C : (hov ? 0xFF3A4452 : 0xFF2E353F));
				frameRect(b.x, b.y, b.w, b.h, b.active ? 0xFFFFD16C : 0xFF48515D, 1);
				var bt = panelBtnTexts[i];
				setTextIfChanged(bt, b.label);
				bt.setPosition(b.x + (b.w - bt.width) * 0.5, b.y + (b.h - bt.height) * 0.5);
				bt.visible = true;
			}
			if (ex.prevH > 0) drawPanelEasePreview(PANEL_X + 14, ex.prevY, PANEL_W - 28, ex.prevH);
		}
	}

	function zoomSliderRect():{x:Float, y:Float, w:Float, h:Float}
		return {x: 28, y: timelineTopY + 5, w: 98, h: 16};

	function setZoomFromSlider(mx:Float):Void
	{
		var r = zoomSliderRect();
		var t = Math.max(0, Math.min(1, (mx - r.x) / r.w));
		var cx = TL_X + (FlxG.width - TL_X) * 0.5;
		var anchor = timeAt(cx);
		pps = 14 * Math.pow(600 / 14, t);
		scrollMs = Math.max(0, anchor - (cx - TL_X) / pps * 1000);
		clampTimelineScroll();
	}

	function finishMarquee(mx:Float, my:Float):Void
	{
		if (Math.abs(mx - marqueeX0) + Math.abs(my - marqueeY0) < 4)
		{
			// คลิกเฉย ๆ บนพื้นที่ว่าง = ยกเลิกการเลือกและย้าย playhead
			if (!marqueeAdd) multiSel = [];
			selected = null;
			selectedChartSource = null;
			selectedChartComponent = null;
			refreshEventValueInputs();
			var wasPlaying = playing;
			if (wasPlaying) setPlayback(false);
			seekTo(timeAt(mx));
			if (wasPlaying) setPlayback(true);
			return;
		}
		var left = Math.min(mx, marqueeX0), right = Math.max(mx, marqueeX0);
		var top = Math.min(my, marqueeY0), bottom = Math.max(my, marqueeY0);
		var picked:Array<CamEvent> = marqueeAdd ? multiSel.copy() : [];
		for (e in events)
		{
			var bx = xAt(e.time);
			var bw = e.track == 'general' ? GEN_W : Math.max(16, e.duration * pps / 1000);
			var by = trackY(e.track, layerOf(e));
			if (bx < right && bx + bw > left && by < bottom && by + rowH() > top && picked.indexOf(e) < 0) picked.push(e);
		}
		multiSel = picked;
		selected = picked.length > 0 ? picked[picked.length - 1] : null;
		selectedChartSource = null;
		selectedChartComponent = null;
		refreshEventValueInputs();
		status('เลือก ${picked.length} events');
	}

	function timelineZoomBy(factor:Float):Void
	{
		var cx = TL_X + (FlxG.width - TL_X) * 0.5;
		var anchor = timeAt(cx);
		pps = Math.max(14, Math.min(600, pps * factor));
		scrollMs = Math.max(0, anchor - (cx - TL_X) / pps * 1000);
		clampTimelineScroll();
	}

	function zoomButtonRect(plus:Bool):{x:Float, y:Float, w:Float, h:Float}
		return {x: plus ? 128 : 6, y: timelineTopY + 3, w: 16, h: 20};

	function handleZoomButtons(mx:Float, my:Float):Bool
	{
		for (plus in [false, true])
		{
			var r = zoomButtonRect(plus);
			if (!inRect(mx, my, r.x, r.y, r.w, r.h)) continue;
			timelineZoomBy(plus ? 1.25 : 0.8);
			return true;
		}
		return false;
	}

	function selectedEditableEvents():Array<CamEvent>
	{
		if (multiSel.length > 0) return multiSel.copy();
		return selected != null && events.indexOf(selected) >= 0 ? [selected] : [];
	}

	function selectAllEvents():Void
	{
		multiSel = events.copy();
		selected = multiSel.length > 0 ? multiSel[multiSel.length - 1] : null;
		selectedChartSource = null;
		selectedChartComponent = null;
		refreshEventValueInputs();
		status('เลือก ${multiSel.length} events');
	}

	function addMany(list:Array<CamEvent>):Void
	{
		if (list.length == 0) return;
		var cmd = new CamCmd(() ->
		{
			for (e in list) if (events.indexOf(e) < 0) events.push(e);
			sortEvents();
		}, () ->
		{
			for (e in list) events.remove(e);
			multiSel = [];
			cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
			cameraEventListDirty = true;
			syncCameraEvents();
			if (selected != null && events.indexOf(selected) < 0) selected = null;
		});
		cmd.ev = list[list.length - 1];
		pushCmd(cmd, true);
		selected = list[list.length - 1];
		multiSel = list.length > 1 ? list.copy() : [];
		selectedChartSource = null;
		selectedChartComponent = null;
		refreshEventValueInputs();
	}

	function removeMany(list:Array<CamEvent>):Void
	{
		if (list.length == 0) return;
		var cmd = new CamCmd(() ->
		{
			for (e in list) events.remove(e);
			multiSel = [];
			cameraEventCacheDirty = true; pauseHold = false; // key เปลี่ยน: เลิกค้าง VCam
			cameraEventListDirty = true;
			syncCameraEvents();
			if (selected != null && events.indexOf(selected) < 0)
			{
				selected = null;
				selectedChartSource = null;
				selectedChartComponent = null;
				refreshEventValueInputs();
			}
		}, () ->
		{
			for (e in list) if (events.indexOf(e) < 0) events.push(e);
			sortEvents();
		});
		pushCmd(cmd, true);
		status('ลบ ${list.length} events');
	}

	function copySelection():Void
	{
		var source = multiSel.length > 0 ? multiSel : (selected != null ? [selected] : []);
		clipboard = [];
		for (e in source)
			if ((e.track == 'focus' || e.track == 'zoom' || e.track == 'tilt' || e.track == 'kick') && e.target != -2) clipboard.push(copyEv(e));
		status(clipboard.length > 0 ? 'คัดลอก ${clipboard.length} events (Ctrl+V วางที่ playhead)' : 'ไม่มี event ที่คัดลอกได้');
	}

	function pasteClipboard():Void
	{
		if (clipboard.length == 0)
		{
			status('Clipboard ว่าง: เลือก event แล้วกด Ctrl+C ก่อน');
			return;
		}
		var minT = clipboard[0].time;
		for (c in clipboard) minT = Math.min(minT, c.time);
		var added:Array<CamEvent> = [];
		for (c in clipboard)
		{
			var e = copyEv(c);
			e.time = Math.max(0, Math.min(songLen, songPos + c.time - minT));
			e.duration = Math.max(0, Math.min(songLen - e.time, e.duration));
			added.push(e);
		}
		addMany(added);
		status('วาง ${added.length} events ที่ ${fmtTime(songPos)}');
	}

	function commitGroupMove(list:Array<CamEvent>, olds:Array<CamEvent>):Void
	{
		var news = [for (e in list) copyEv(e)];
		var changed = false;
		for (i in 0...list.length)
			if (!sameEv(olds[i], news[i])) changed = true;
		if (!changed) return;
		var cmd = new CamCmd(() ->
		{
			for (i in 0...list.length) applyEv(list[i], news[i]);
		}, () ->
		{
			for (i in 0...list.length) applyEv(list[i], olds[i]);
		});
		cmd.ev = list[0];
		pushCmd(cmd, false);
	}

	function sectionIndexAt(t:Float):Int
	{
		for (i in 0...sectionCameraTargets.length)
			if (t >= sectionCameraTargets[i].time && t < sectionEnds[i]) return i;
		return -1;
	}

	function whoName(who:Int):String
		return who == 0 ? 'BF' : (who == 1 ? 'Opponent' : 'GF');

	static function whoShort(who:Int):String
		return who == 0 ? 'BF' : (who == 1 ? 'OPP' : 'GF');

	static function whoColor(who:Int):FlxColor
		return who == 0 ? 0xFF2F6FB0 : (who == 1 ? 0xFFB04A4A : 0xFFB05A9A);

	inline function generalWidth():Float
		return GEN_W;

	/** ช่องอัตโนมัติขึ้นเฉพาะตอน "เริ่มหันไปหาคนใหม่" (Section แรก หรือคนที่หันเปลี่ยนจาก Section ก่อนหน้า) */
	inline function isAutoChange(si:Int):Bool
		return si == 0 || sectionWho[si] != sectionWho[si - 1];

	/** มี General key ที่ผู้ใช้วางเองอยู่ใน Section นี้แล้วหรือยัง (ถ้ามี ช่องอัตโนมัติของ Section นั้นจะไม่ถูกวาด) */
	function sectionHasGeneral(si:Int):Bool
	{
		var t0 = sectionCameraTargets[si].time - 1;
		var t1 = sectionEnds[si];
		for (e in events)
			if (e.track == 'general' && e.time >= t0 && e.time < t1) return true;
		return false;
	}

	/** ช่องอัตโนมัติ (จางๆ) ของ Section ใต้เมาส์ ถ้าคลิกจะกลายเป็น General key ที่แก้ไขได้ */
	function hitAutoSection(mx:Float, my:Float):Int
	{
		if (!inRect(mx, my, TL_X, trackY("general"), FlxG.width - TL_X, rowH())) return -1;
		for (si in 0...sectionCameraTargets.length)
		{
			var x = xAt(sectionCameraTargets[si].time);
			if (isAutoChange(si) && mx >= x && mx <= x + GEN_W && !sectionHasGeneral(si)) return si;
		}
		return -1;
	}

	function vScrollTrack():{x:Float, y:Float, w:Float, h:Float}
		return {x: FlxG.width - 12, y: timelineTopY + RULER_H, w: 10, h: tlHeight() - RULER_H};

	function vScrollThumbH():Float
	{
		var tr = vScrollTrack();
		return Math.max(20, tr.h * tr.h / Math.max(1, rowH() * rowCount()));
	}

	function vScrollThumbY():Float
	{
		var tr = vScrollTrack();
		var maxScroll = maxLayerScroll();
		return maxScroll > 0 ? tr.y + (tr.h - vScrollThumbH()) * layerScrollY / maxScroll : tr.y;
	}

	function setVScroll(my:Float):Void
	{
		var tr = vScrollTrack();
		var ratio = (my - vScrollGrab - tr.y) / Math.max(1, tr.h - vScrollThumbH());
		layerScrollY = ratio * maxLayerScroll();
		clampLayerScroll();
	}

	function hit(mx:Int, my:Int):CamEvent
	{
		var i = events.length;
		while (i-- > 0)
		{
			var e = events[i];
			if (e.track == 'kick') continue;
			var x = xAt(e.time);
			var w = e.track == 'general' ? GEN_W : Math.max(16, e.duration * pps / 1000) + 5; // +5 = จับเลยขอบขวาได้เล็กน้อย
			if (inRect(mx, my, x, trackY(e.track, layerOf(e)), w, rowH()))
				return e;
		}
		i = chartCameraEvents.length;
		while (i-- > 0)
		{
			var e = chartCameraEvents[i];
			var sourceLink = chartCameraLinkFor(e);
			if (sourceLink != null && !chartCameraLinkVisible(sourceLink)) continue;
			var x = xAt(e.time);
			var w = Math.max(16, e.duration * pps / 1000);
			if (inRect(mx, my, x, trackY(e.track, layerOf(e)), w, rowH()))
				return e;
		}
		return null;
	}

	function syncStageHostMembers():Void
	{
		if (stageHost == null || stageHost.members == null || stageHost.members.length == 0) return;
		// Drain from the end in place. Copying the whole group every update caused
		// avoidable short-lived allocations whenever a stage script adds a sprite.
		while (stageHost.members.length > 0)
		{
			var index = stageHost.members.length - 1;
			var item = stageHost.members[index];
			stageHost.remove(item, true);
			if (item == null) continue;
			if (!members.contains(item)) add(item);
			setTreeCamera(item, previewCamera);
			trackDynamicPreviewMember(item);
		}
	}

	/** Snapshot nested stage groups after setup so runtime particles and script-created
	 *  children can be tracked separately from the scene's permanent objects. */
	function capturePreviewGroupMemberBaselines():Void
	{
		previewGroupMemberBaselines = new ObjectMap();
		var pending:Array<FlxBasic> = [];
		var visited:Array<FlxBasic> = [];
		for (item in members)
			if (item != null) pending.push(item);
		for (stage in stages)
			if (stage != null) pending.push(stage);

		while (pending.length > 0)
		{
			var item = pending.pop();
			if (item == null || visited.indexOf(item) >= 0) continue;
			visited.push(item);
			var children:Dynamic = Reflect.field(item, 'members');
			if (children == null || !Std.isOfType(children, Array) || children == members) continue;

			var baseline:Array<FlxBasic> = [];
			for (child in (cast children:Array<Dynamic>))
				if (child != null && Std.isOfType(child, FlxBasic))
				{
					baseline.push(cast child);
					pending.push(cast child);
				}
			previewGroupMemberBaselines.set(item, baseline);
		}
	}

	/** Keep nested stage/script groups bounded as well as the direct state member list. */
	function pruneNestedPreviewMembers():Void
	{
		var pending:Array<FlxBasic> = [];
		var visited:Array<FlxBasic> = [];
		var currentDynamicChildren:Array<{parent:FlxBasic, child:FlxBasic}> = [];
		var nextBaselines:ObjectMap<FlxBasic, Array<FlxBasic>> = new ObjectMap();
		for (item in members)
			if (item != null) pending.push(item);
		for (stage in stages)
			if (stage != null) pending.push(stage);

		while (pending.length > 0)
		{
			var item = pending.pop();
			if (item == null || visited.indexOf(item) >= 0) continue;
			visited.push(item);
			var children:Dynamic = Reflect.field(item, 'members');
			if (children == null || !Std.isOfType(children, Array) || children == members) continue;

			var memberList:Array<Dynamic> = cast children;
			var baseline = previewGroupMemberBaselines.get(item);
			if (baseline == null) baseline = [];
			nextBaselines.set(item, baseline);
			for (child in memberList)
				if (child != null && Std.isOfType(child, FlxBasic))
				{
					var basic:FlxBasic = cast child;
					pending.push(basic);
					if (!baseline.contains(basic))
					{
						var duplicate = false;
						for (entry in currentDynamicChildren)
							if (entry.parent == item && entry.child == basic) { duplicate = true; break; }
						if (!duplicate) currentDynamicChildren.push({parent: item, child: basic});
					}
				}
		}

		// Drop children that the stage already removed, then append newly observed ones
		// to the FIFO so particle bursts cannot grow a group forever.
		var nextDynamicChildren:Array<{parent:FlxBasic, child:FlxBasic}> = [];
		for (entry in dynamicPreviewGroupChildren)
			for (current in currentDynamicChildren)
				if (entry.parent == current.parent && entry.child == current.child)
				{
					nextDynamicChildren.push(entry);
					break;
				}
		for (current in currentDynamicChildren)
		{
			var alreadyTracked = false;
			for (entry in nextDynamicChildren)
				if (entry.parent == current.parent && entry.child == current.child) { alreadyTracked = true; break; }
			if (!alreadyTracked) nextDynamicChildren.push(current);
		}
		dynamicPreviewGroupChildren = nextDynamicChildren;
		previewGroupMemberBaselines = nextBaselines;

		while (dynamicPreviewGroupChildren.length > MAX_NESTED_DYNAMIC_PREVIEW_MEMBERS)
		{
			var oldest = dynamicPreviewGroupChildren.shift();
			if (oldest == null || oldest.parent == null || oldest.child == null) continue;
			var parentMembers:Dynamic = Reflect.field(oldest.parent, 'members');
			if (parentMembers == null || !Std.isOfType(parentMembers, Array) || !(cast parentMembers:Array<Dynamic>).contains(oldest.child)) continue;
			try
			{
				var removeMethod = Reflect.field(oldest.parent, 'remove');
				if (removeMethod != null) Reflect.callMethod(oldest.parent, removeMethod, [oldest.child, true]);
			}
			catch (_:Dynamic) {}
			// Fallback for group-like objects whose remove method isn't reflectable.
			if ((cast parentMembers:Array<Dynamic>).contains(oldest.child))
				(cast parentMembers:Array<Dynamic>).remove(oldest.child);
			var evictedTree = collectPreviewMemberTree(oldest.child);
			var retainedChildren:Array<{parent:FlxBasic, child:FlxBasic}> = [];
			for (entry in dynamicPreviewGroupChildren)
				if (evictedTree.indexOf(entry.parent) < 0 && evictedTree.indexOf(entry.child) < 0)
					retainedChildren.push(entry);
			dynamicPreviewGroupChildren = retainedChildren;
			oldest.child.destroy();
		}
	}

	function collectPreviewMemberTree(root:FlxBasic):Array<FlxBasic>
	{
		var tree:Array<FlxBasic> = [];
		var pending:Array<FlxBasic> = [root];
		while (pending.length > 0)
		{
			var item = pending.pop();
			if (item == null || tree.indexOf(item) >= 0) continue;
			tree.push(item);
			var children:Dynamic = Reflect.field(item, 'members');
			if (children == null || !Std.isOfType(children, Array) || children == members) continue;
			for (child in (cast children:Array<Dynamic>))
				if (child != null && Std.isOfType(child, FlxBasic)) pending.push(cast child);
		}
		return tree;
	}

	function trackDynamicPreviewMember(item:FlxBasic):Void
	{
		if (item == null || dynamicPreviewMembers.indexOf(item) >= 0) return;
		dynamicPreviewMembers.push(item);
		while (dynamicPreviewMembers.length > MAX_DYNAMIC_PREVIEW_MEMBERS)
		{
			var oldest = dynamicPreviewMembers.shift();
			if (oldest != null && members.contains(oldest))
			{
				remove(oldest, true);
				oldest.destroy();
			}
		}
	}

	// =====================================================================
	//  Update
	// =====================================================================
	function isProtectedPreviewSound(sound:FlxSound):Bool
		return sound == null || sound == inst || sound == vocals || sound == opponentVocals
			|| sound == FlxG.sound.music || sound == editorMenuMusic || soundsBeforeEditor.indexOf(sound) >= 0;

	function removePreviewScriptSound(sound:FlxSound):Void
	{
		if (sound == null || isProtectedPreviewSound(sound)) return;
		if (FlxG.sound.music == sound) FlxG.sound.music = null;
		sound.stop();
		FlxG.sound.list.remove(sound);
		sound.destroy();
	}

	/** Keep transient mod audio bounded while preserving the real gameplay song and vocals. */
	function prunePreviewScriptSounds():Void
	{
		var sounds = FlxG.sound.list.members;
		var activeScriptSounds = 0;
		var i = sounds.length;
		while (i-- > 0)
		{
			var sound = sounds[i];
			if (isProtectedPreviewSound(sound)) continue;
			// Completed one-shots should not stay in the global sound manager if a mod
			// disabled FlxSound's usual auto-destroy behavior.
			if (!sound.playing && sound.autoDestroy)
			{
				removePreviewScriptSound(sound);
				continue;
			}
			activeScriptSounds++;
		}
		while (activeScriptSounds > MAX_PREVIEW_SCRIPT_SOUNDS)
		{
			var oldestIndex = 0;
			while (oldestIndex < sounds.length && isProtectedPreviewSound(sounds[oldestIndex])) oldestIndex++;
			if (oldestIndex >= sounds.length) break;
			removePreviewScriptSound(sounds[oldestIndex]);
			activeScriptSounds--;
		}
	}

	function maintainLiveGameplayResources(elapsed:Float):Void
	{
		if (!playing)
		{
			previewResourceSweepAccumulator = 0;
			previewCacheSweepAccumulator = 0;
			previewMemoryGcAccumulator = 0;
			return;
		}
		previewResourceSweepAccumulator += elapsed;
		if (previewResourceSweepAccumulator >= 1)
		{
			previewResourceSweepAccumulator = 0;
			prunePreviewScriptSounds();
		}
		previewCacheSweepAccumulator += elapsed;
		if (previewCacheSweepAccumulator >= 5)
		{
			previewCacheSweepAccumulator = 0;
			pruneUnusedPreviewCache();
		}
		#if cpp
		// Script hooks run at gameplay cadence and can create short-lived Haxe objects.
		// A periodic major collection keeps the editor's native heap from retaining their
		// high-water mark for the entire song.
		previewMemoryGcAccumulator += elapsed;
		if (previewMemoryGcAccumulator >= 12)
		{
			previewMemoryGcAccumulator = 0;
			cpp.vm.Gc.run(true);
			cpp.vm.Gc.compact();
		}
		#end
	}

	/** Release cached assets left behind by finished preview effects and sounds. */
	function pruneUnusedPreviewCache():Void
	{
		// This keeps graphics referenced by live sprites, including sprites retained
		// by scripts, and removes only unused tracked graphics.
		CacheSystem.freeGraphicsFromMemory();

		var protectedSounds:Array<openfl.media.Sound> = [];
		for (sound in FlxG.sound.list.members)
			if (sound != null)
			{
				var asset:Dynamic = Reflect.field(sound, '_sound');
				if (asset != null) protectedSounds.push(cast asset);
			}
		for (sound in soundsBeforeEditor)
			if (sound != null)
			{
				var asset:Dynamic = Reflect.field(sound, '_sound');
				if (asset != null && !protectedSounds.contains(cast asset)) protectedSounds.push(cast asset);
			}
		CacheSystem.freeUnusedSoundsFromMemory(protectedSounds);

		// Asset keys no longer present in either cache have no reason to remain in
		// the per-state keep list. Deduplicate keys added by legacy loading paths too.
		var liveKeys:Array<String> = [];
		for (key in CacheSystem.localTrackedAssets)
			if ((CacheSystem.currentTrackedAssets.exists(key) || CacheSystem.currentTrackedSounds.exists(key)) && !liveKeys.contains(key))
				liveKeys.push(key);
		CacheSystem.localTrackedAssets = liveKeys;
	}

	function updatePreviewStageScripts(elapsed:Float, postUpdate:Bool):Void
	{
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		if (!playing || stageHost == null) return;
		if (!postUpdate)
		{
			stageHost.setOnScripts('songPosition', songPos);
			stageHost.setOnScripts('curDecStep', Conductor.getStep(songPos));
			stageHost.setOnScripts('curDecBeat', Conductor.getBeat(songPos));
		}
		var beforeFollowX = stageHost.camFollow == null ? 0 : stageHost.camFollow.x;
		var beforeFollowY = stageHost.camFollow == null ? 0 : stageHost.camFollow.y;
		var beforeZoom = FlxG.camera.zoom;
		var beforeDefaultZoom = stageHost.defaultCamZoom;
		var callback = postUpdate ? 'onUpdatePost' : 'onUpdate';
		previewStageUpdateArgs[0] = elapsed;
		try stageHost.callOnScripts(callback, previewStageUpdateArgs) catch (e:Dynamic) trace('Camera Editor stage $callback: $e');
		capturePreviewScriptCameraChanges(beforeFollowX, beforeFollowY, beforeZoom, beforeDefaultZoom);
		#end
	}

	override function update(elapsed:Float)
	{
		if (createFailed) return;
		restoreRealCameraView(); // กันกรณีเฟรมก่อนวาดไม่ครบ ให้ PlayState เห็นกล้องจริงเสมอ
		enforceEditorCameras();
		if (disableSongLua) applySongLuaSetting(); // สคริปต์ที่เพิ่งโหลดระหว่างทางก็ถูกปิดด้วย
		var wasPlaying = playing;
		var hadTextFocus = PsychUIInputText.focusOn != null;
		suppressInputEnterShortcut = hadTextFocus && (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.F2);
		// This calls the real PlayState update first: chart events, gameplay scripts,
		// stage updates, character animations, and camera zooms all use the same path.
		super.update(elapsed);
		// FlxSound clears its playing state after dispatching onComplete. Restart only now,
		// after super.update returns, so that cleanup cannot immediately stop the restarted sound.
		if (previewEndPending) resolvePreviewSongEnd();
		#if VIDEOS_ALLOWED
		// VideoSprite is a screen-space overlay; the editor transport explicitly owns whether it runs.
		if (!playing && previewEventVideo != null) previewEventVideo.pause();
		#end
		var audioPlaying = !paused && FlxG.sound.music != null && FlxG.sound.music.playing;
		if (holdInitialStart && audioPlaying)
		{
			// PlayState เริ่มเพลง/นับถอยหลังเองตอนเข้า editor: หยุดไว้ที่ต้นเพลงจนกว่าผู้ใช้จะกด Play
			pauseCameraEditorPlayback();
			seekTo(0);
			audioPlaying = false;
			wasPlaying = false;
		}
		if (wasPlaying || playing || audioPlaying)
			songPos = Math.max(0, Math.min(songLen, Conductor.songPosition));
		// `playing` tracks the editor's intended state. Audio completion temporarily sets
		// music.playing=false before finishPreviewSong restarts it; do not erase the loop intent here.
		updateTimelineFollow();
		if (multiSel.length > 0) multiSel = multiSel.filter(e -> events.indexOf(e) >= 0);
		handleKeys();
		handleMouse();
		computePreviewViewport();
		updateEditorCursor(FlxG.mouse.gameX, FlxG.mouse.gameY);
		autosaveTick(elapsed);
		updatePreviewCamera(elapsed);
		if (needInitialFit && stageHost != null)
		{
			needInitialFit = false;
			fitPreview(); // ให้กรอบ VCam (ขนาดจอจริง) พอดีพรีวิวตั้งแต่เปิด
		}
		if (eventReplayPending && mode != Seek)
			replayEventsTo(songPos);
		syncPreviewCharacterPose();
		// Custom chart scripts may install their own full-frame filters during playback.
		// Keep the scene camera renderable in the editor's smaller viewport.
		if (cameraEditorMode && camGame != null && camGame.filters != null && camGame.filters.length > 0)
			camGame.filters = [];
		maintainLiveGameplayResources(elapsed);
		lastPreviewTime = songPos;
		redraw();
	}

	function updatePreviewCamera(elapsed:Float):Void
	{
		if (previewCamera == null) return;
		if (!playing && stageHost != null)
		{
			// ตอนหยุด: ตั้งกล้องเกมจริงให้ตรงกับ pose ของ timeline ทุกเฟรม (แก้ค่า event แล้วเห็นทันที)
			// ทำทั้ง Relative และ Free View: VCam อ่านจากกล้องจริงเสมอ (ดู draw) มุมมองของ editor ไม่โดนกระทบ
			// เพราะ draw() ใส่ scroll/zoom ของ editor ทับตอนวาดแล้วคืนค่าจริงทีหลัง
			resetVcamDiagnostics();
			var pose = pauseHold ? pauseHoldPose : evalAt(songPos);
			previewCameraEditorPose(pose.x, pose.y, pose.zoom, chartFocusActive(songPos));
			vcamPose.x = pose.x;
			vcamPose.y = pose.y;
			vcamPose.zoom = pose.zoom;
		}
		else
		{
			// ตอนเล่น: ให้ timeline (event ที่แก้ใน editor + chart) เป็นคนกำหนดเป้าหมายของกล้องจริง
			// แล้ว VCam = กล้องจริงที่ PlayState คุมอยู่ (follow lerp / zoom bop เหมือนในเกม)
			driveRealCameraFromTimeline(elapsed);
			vcamPose.x = previewCamera.scroll.x + previewCamera.width * 0.5;
			vcamPose.y = previewCamera.scroll.y + previewCamera.height * 0.5;
			vcamPose.zoom = previewCamera.zoom;
		}
		applyTimelineTilt(); // Tilt key ของ timeline เขียนมุมกล้องจริงหลัง PlayState / Lua อัปเดตแล้ว
		vcamAngle = previewCamera.angle; // draw() คืนค่าจริงหลัง render เสมอ จึงอ่านค่า event/lua ได้ตรงนี้
		// Relative View: มุมมองล็อกตาม VCam ส่วน Free View: มุมมองอยู่กับที่จนกว่าจะลากเอง
		if (relativeView)
		{
			viewCenterX = vcamPose.x;
			viewCenterY = vcamPose.y;
		}
	}

	function resetVcamDiagnostics():Void
	{
		vcamTimelineOwned = false;
		vcamWasFocusOwned = false;
	}

	/**
	 * ตอนเล่น: ให้ timeline (event ที่แก้ใน editor + chart) กำหนดกล้องจริงผ่าน camFollow / defaultCamZoom / zoom kick
	 * ที่มาของบั๊ก "กล้องไม่ตาม event": PlayState.setCameraEditorEvents() แค่เก็บ list ไว้ ไม่เคยใช้ขับกล้อง
	 * และ triggerEvent(preview=true) ข้าม Camera Follow Pos / Add Camera Zoom โดยบอกว่า "timeline เป็นเจ้าของ"
	 * แต่ตอนเล่นไม่มีใครเรียก evalAt() เลย ฟังก์ชันนี้จึงเป็นตัวขับกล้องตอนเล่น
	 * ช่วงที่ไม่มี focus / zoom event ไม่แตะอะไร PlayState / สคริปต์คุมเองตามเดิม
	 * กล้องจริงยังเคลื่อนด้วย follow lerp และ zoom bop ของ PlayState เหมือนในเกม VCam อ่านจากกล้องจริงนั้น
	 */
	function driveRealCameraFromTimeline(elapsed:Float):Void
	{
		var follow = stageHost == null ? null : stageHost.camFollow;
		if (stageHost == null || follow == null)
		{
			resetVcamDiagnostics();
			return;
		}
		var focusOwned = chartFocusActive(songPos); // เรียก rebuildCameraEventCache ให้แล้ว
		var zoomOwned = chartZoomActive(songPos);

		// Add Camera Zoom (kick): preview=true ถูกข้ามใน PlayState จึงใส่แรงกระตุกซูมเองตอน playhead เดินผ่าน
		var delta = songPos - lastPreviewTime;
		if (lastPreviewTime >= 0 && delta > 0 && delta < 250 && ClientPrefs.data.camZooms)
		{
			var kickFrom = upperBoundCameraEvents(zoomKickEvents, lastPreviewTime);
			var kickTo = upperBoundCameraEvents(zoomKickEvents, songPos);
			for (i in kickFrom...kickTo)
				if (previewCamera.zoom < stageHost.defaultCamZoom + 0.3) previewCamera.zoom += zoomKickEvents[i].zoom;
		}

		vcamTimelineOwned = focusOwned || zoomOwned;
		if (!focusOwned && vcamWasFocusOwned)
		{
			// ปล่อย focus (Camera Follow Pos ว่าง): กลับไปตาม section และคืนสิทธิ์ให้ sectionHit ย้ายกล้อง
			var released = chartCameraAt(songPos);
			follow.setPosition(released.x, released.y);
			@:privateAccess stageHost.isCameraOnForcedPos = false;
		}
		vcamWasFocusOwned = focusOwned;
		if (!vcamTimelineOwned) return;

		var hookDefaultZoom = stageHost.defaultCamZoom;
		var hookDecay = stageHost.camZoomingDecay;
		// evalAt มีผลข้างเคียง: เขียน defaultCamZoom = zoom ของ timeline (ยังไม่รวม bop/kick ซึ่ง PlayState ทำเอง)
		var pose = evalAt(songPos);
		var timelineZoom = stageHost.defaultCamZoom;
		stageHost.camZoomingDecay = hookDecay; // decay เป็นของ PlayState / สคริปต์
		if (!zoomOwned) stageHost.defaultCamZoom = hookDefaultZoom; // ไม่มี zoom event: อย่าทับ zoom ของสคริปต์
		vcamExpected.x = pose.x;
		vcamExpected.y = pose.y;
		vcamExpected.zoom = zoomOwned ? timelineZoom : hookDefaultZoom;
		// Warp (duration <= 0): playhead เพิ่งเดินผ่าน key ที่สั่งให้ "โดดทันที" ในเฟรมนี้หรือไม่
		// กล้องจริงของ PlayState ตาม camFollow ด้วย followLerp (~0.04) จึงค่อย ๆ เลื่อนตามไป ต้อง snap เองให้ VCam ไปด้วยทันที
		var warpFocus = false;
		var warpZoom = false;
		if (lastPreviewTime >= 0 && songPos > lastPreviewTime)
		{
			warpFocus = focusOwned && crossedWarpKey(focusCameraEvents, lastPreviewTime, songPos);
			warpZoom = zoomOwned && crossedWarpKey(zoomCameraEvents, lastPreviewTime, songPos);
		}
		// Also apply the active zero-duration focus key when playback starts/seeks exactly on it.
		// A snapToTarget() call alone can still be followed by FlxCamera's lerp in a custom engine.
		var activeFocusCount = upperBoundCameraEvents(focusCameraEvents, songPos);
		if (focusOwned && activeFocusCount > 0 && focusCameraEvents[activeFocusCount - 1].duration <= 0)
			warpFocus = true;
		if (focusOwned)
		{
			follow.setPosition(pose.x, pose.y);
			@:privateAccess stageHost.isCameraOnForcedPos = true; // sectionHit ไม่ดึงกล้องกลับไปที่ตัวละคร
			if (warpFocus)
				stageHost.previewCameraEditorPose(pose.x, pose.y, previewCamera.zoom, true); // hard set actual scroll; no camera lerp animation
		}
		// camZooming ปิดอยู่ (เช่นก่อนโน้ตแรก) PlayState ไม่ lerp zoom เข้า defaultCamZoom จึงตั้งให้ตรง
		// Warp ของ zoom: PlayState จะ lerp zoom เข้า defaultCamZoom ช้า ๆ จึงตั้งให้ตรงทันทีเช่นกัน
		if (zoomOwned && (warpZoom || !stageHost.camZooming)) previewCamera.zoom = timelineZoom;
	}

	/** มี key ที่เป็น Warp (duration <= 0) อยู่ในช่วง (from, to] หรือไม่ (ใช้ตรวจว่า playhead เพิ่งเดินผ่าน Warp) */
	function crossedWarpKey(list:Array<CamEvent>, from:Float, to:Float):Bool
	{
		var first = upperBoundCameraEvents(list, from);
		var last = upperBoundCameraEvents(list, to);
		for (i in first...last)
			if (list[i].duration <= 0) return true;
		return false;
	}

	/** Free View ไม่ได้ขยับกล้องเกมระหว่างหยุด จึงต้องวางกล้องให้ตรง timeline หนึ่งครั้งก่อนเริ่มเล่น */
	function snapGameCameraToTimeline():Void
	{
		if (previewCamera == null || stageHost == null || relativeView) return;
		var pose = evalAt(songPos);
		previewCameraEditorPose(pose.x, pose.y, pose.zoom, false);
	}

	function getPreviewCharacter(who:Int):Character
		return who >= 0 && who < previewCharacters.length ? previewCharacters[who] : null;

	function playPreviewAnimation(who:Int, anim:String, ?resetHold:Bool = true, ?until:Float = 0):Void
	{
		var char = getPreviewCharacter(who);
		if (char == null || char.animation == null) return;
		var chosen = anim;
		if (char.animation.getByName(chosen) == null && camEndsWith(chosen, '-alt'))
			chosen = chosen.substr(0, chosen.length - 4);
		if (char.animation.getByName(chosen) == null)
		{
			if (camStartsWith(chosen, 'sing') && char.animation.getByName('idle') != null) chosen = 'idle';
			else return;
		}
		char.playAnim(chosen, true);
		if (resetHold)
		{
			previewActionUntil[who] = until;
			previewSinging[who] = camStartsWith(chosen, 'sing') || chosen == 'hey';
		}
	}

	function danceCharacter(who:Int):Void
	{
		var char = getPreviewCharacter(who);
		if (char != null)
		{
			char.specialAnim = false;
			char.dance();
		}
		if (who >= 0 && who < previewSinging.length) previewSinging[who] = false;
	}

	function syncPreviewCharactersFromHost():Void
	{
		if (stageHost == null) return;
		previewCharacters[0] = stageHost.boyfriend;
		previewCharacters[1] = stageHost.dad;
		previewCharacters[2] = stageHost.gf;
		for (who in 0...previewCharacters.length)
		{
			var char = previewCharacters[who];
			previewSinging[who] = false;
			if (char != null)
			{
				setTreeCamera(char, previewCamera);
				charPos[who] = stageHost.getCharCamPos(who);
			}
		}
		buildSectionCameraCache();
	}

	function previewNoteUntil(note:PreviewNote):Float
	{
		var char = getPreviewCharacter(note.who);
		var singDuration = char == null ? 4 : char.singDuration;
		var stepMs = Conductor.getCrotchetAtTime(note.time) / 4;
		// Match PlayState's sing hold timing and let sustains finish before returning to idle.
		return note.time + Math.max(250, note.sustain) + stepMs * 1.1 * singDuration;
	}

	/** ขยับเฟรมของแอนิเมชันปัจจุบันให้ตรงกับเวลาที่ผ่านไปหลังโน้ต เพื่อให้ท่าตอน scrub ตรงตำแหน่งเพลงจริง ๆ */
	function seekCharacterAnimationFrame(who:Int, elapsedMs:Float):Void
	{
		var char = getPreviewCharacter(who);
		if (char == null || char.animation == null) return;
		var anim = char.animation.curAnim;
		if (anim == null || anim.frames == null || anim.frames.length == 0 || anim.frameRate <= 0) return;
		var frame = Std.int(Math.max(0, elapsedMs) / 1000 * anim.frameRate);
		var count = anim.frames.length;
		anim.curFrame = anim.looped ? frame % count : Std.int(Math.min(frame, count - 1));
	}

	/**
	 * ย้อนกลับ/กรอ แบบ "Sing backwards" สำหรับอีเวนต์และ Lua:
	 * คืนสถานะตัวละคร/สไตรม์/ตัวนับซูมเป็นตอนเริ่มเพลง (ชุดเดียวกับ PlayState.finishRestart) เรียก onRestartSongPost
	 * แล้วเล่นอีเวนต์ทุกตัวที่เกิดก่อนตำแหน่งใหม่ซ้ำตามลำดับ โดยไม่ยุ่งกับกล้อง (timeline เป็นเจ้าของกล้องอยู่แล้ว)
	 */
	function replayEventsTo(time:Float):Void
	{
		eventReplayPending = false;
		if (stageHost == null || !generatedMusic) return;
		try
		{
			if (cameraEditorChartDirty) rebuildCameraEditorEvents();

			// tween / timer ที่ Lua ค้างไว้จากอนาคตจะสู้กับสถานะที่เรากำลังคืน
			for (key in variables.keys())
			{
				var value:Dynamic = variables.get(key);
				if (Std.isOfType(value, FlxTween)) cast(value, FlxTween).cancel();
				else if (Std.isOfType(value, FlxTimer)) cast(value, FlxTimer).cancel();
			}

			// ให้ Lua รีเซ็ตของตัวเองเหมือนตอนกด Restart Song ใน PlayState (onRestartSong ก่อน, onRestartSongPost ทีหลัง)
			callOnScripts('onRestartSong');
			if (songSpeedTween != null)
			{
				songSpeedTween.cancel();
				songSpeedTween = null;
			}
			// กลับสู่ต้นเพลงจริง: คืนกล้อง (zoom/angle/alpha/FX/tween ที่ Lua ค้างไว้), tempo, ความเร็วโน้ต, คะแนน, เลือด
			if (time <= 1)
			{
				returnCameraToStart(0);
				Conductor.bpm = PlayState.SONG.bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
				songSpeed = restartSongSpeed;
				songScore = 0;
				songHits = 0;
				songMisses = 0;
				combo = 0;
				maxCombo = 0;
				totalPlayed = 0;
				totalNotesHit = 0;
				for (rating in ratingsData) rating.hits = 0;
				ratingPercent = 0;
				ratingFC = '';
				healthLerp = 1;
				health = 1;
				RecalculateRating(false, false);
				for (spr in comboGroup.members.copy())
				{
					if (spr == null) continue;
					FlxTween.cancelTweensOf(spr);
					comboGroup.remove(spr, true);
					spr.destroy();
				}
				curSection = 0;
				stepsToDo = 0;
				setOnScripts('curSection', 0);
			}

			restoreInitialCharacters();
			for (char in [boyfriend, dad, gf])
			{
				if (char == null) continue;
				char.stunned = false;
				char.specialAnim = false;
				char.heyTimer = 0;
				char.holdTimer = 0;
				if (restartIdleSuffix.exists(char.curCharacter))
				{
					char.idleSuffix = restartIdleSuffix.get(char.curCharacter);
					char.recalculateDanceIdle();
				}
				if (restartCharProps.exists(char.curCharacter)) loadSpriteProps(char, restartCharProps.get(char.curCharacter));
			}
			gfSpeed = restartGfSpeed;
			camZoomingMult = restartZoomMult;
			camZoomingFrequency = restartZoomFrequency;
			camZoomingDecay = restartZoomDecay;
			camZooming = songName != 'tutorial' && firstChartNoteTime <= time;
			for (i => strum in strumLineNotes.members)
			{
				if (strum == null) continue;
				FlxTween.cancelTweensOf(strum);
				strum.playAnim('static');
				strum.resetAnim = 0;
				if (i < restartStrumProps.length) loadSpriteProps(strum, restartStrumProps[i]);
			}
			callOnScripts('onRestartSongPost'); // สคริปต์ตั้งค่าท่าเริ่มต้นใหม่ (เหมือนตอนกด Restart)

			// เล่นอีเวนต์ที่ผ่านมาแล้วซ้ำตามลำดับ preview=true: กล้องยังเป็นของ timeline
			for (event in restartEventNotes)
			{
				if (event.strumTime > time) break;
				triggerEvent(event.event, event.value1 == null ? '' : event.value1, event.value2 == null ? '' : event.value2, event.strumTime, true);
			}
			applyCameraEditorEventsFrom(time);
			syncPreviewCharactersFromHost();
		}
		catch (e:Dynamic)
			trace('Camera Editor replay events: $e');
		animSyncDirty = true;
	}

	/** ตัวละครที่ไม่ได้ร้อง: กลับ idle เฉพาะเมื่อยังค้างท่า sing ไม่เรียก dance ซ้ำทุกเฟรมตอนลาก (เดิมทำให้ GF นิ่ง) */
	function settlePreviewCharacter(who:Int):Void
	{
		var char = getPreviewCharacter(who);
		previewSinging[who] = false;
		if (char == null) return;
		var name = char.getAnimationName();
		if (name != null && camStartsWith(name, 'sing')) danceCharacter(who);
	}

	function rebuildPreviewAnimationsAt(time:Float):Void
	{
		previewNoteCursor = -1;
		var latest:Array<Int> = [-1, -1, -1];
		for (i in 0...previewNotes.length)
		{
			if (previewNotes[i].time > time) break;
			if (isPreviewNoteBlocked(previewNotes[i])) continue;
			var who = previewNotes[i].who;
			if (who >= 0 && who < 3 && previewNotes[i].animation.length > 0) latest[who] = i;
			previewNoteCursor = i;
		}
		for (who in 0...3)
		{
			previewSinging[who] = false;
			var ix = latest[who];
			if (ix >= 0 && time <= previewNoteUntil(previewNotes[ix]))
			{
				var note = previewNotes[ix];
				var animName = note.animation;
				var char = getPreviewCharacter(who);
				// PlayState เล่น <anim>-hold ระหว่าง sustain ถ้าตัวละครมีท่านี้
				var stepMs = Conductor.getCrotchetAtTime(note.time) / 4;
				if (char != null && char.animation != null && note.sustain > 0 && time > note.time + stepMs && time <= note.time + note.sustain
					&& char.animation.exists(animName + '-hold'))
					animName += '-hold';
				playPreviewAnimation(who, animName, true, previewNoteUntil(note));
				seekCharacterAnimationFrame(who, time - note.time);
			}
			else
				settlePreviewCharacter(who);
		}
		lastBeatTick = -1;
	}

	/**
	 * ซิงก์ท่าร้อง/ไอเดิลของตัวละครกับตำแหน่งเพลง (เรียลไทม์, scrub, ย้อนกลับ)
	 * - ลากหรือกรอ (หยุดอยู่ / ย้อนกลับ / กระโดดไกล): สร้างท่าที่ตำแหน่งนั้นใหม่ทั้งหมด พร้อมเฟรมที่ตรงเวลา
	 * - เล่นไปข้างหน้า: เล่นท่าเมื่อถึงโน้ตเท่านั้น ไม่ยุ่งกับจังหวะ idle ของ PlayState จึงไม่ทำงานซ้อนกัน
	 */
	function syncPreviewCharacterPose():Void
	{
		if (stageHost == null || previewNotes.length == 0)
		{
			animSyncPos = songPos;
			return;
		}
		var delta = songPos - animSyncPos;
		var jumped = animSyncDirty || delta < -0.5 || Math.abs(delta) > 1000 || (!playing && Math.abs(delta) > 0.5);
		animSyncDirty = false;
		animSyncPos = songPos;
		// เล่นไปข้างหน้าปกติ: PlayState (botplay ใน editor) ร้องเองจากโน้ตจริงอยู่แล้ว จึงไม่เล่นซ้ำ
		// ที่นี่ซิงก์เฉพาะตอน scrub / ย้อนกลับ / กระโดด ซึ่ง PlayState ทิ้งโน้ตที่ผ่านไปแล้ว ท่าจึงต้องสร้างใหม่เอง
		if (jumped)
			rebuildPreviewAnimationsAt(songPos);
		else
			while (previewNoteCursor + 1 < previewNotes.length && previewNotes[previewNoteCursor + 1].time <= songPos)
				previewNoteCursor++;
		for (who in 0...3)
		{
			if (!previewSinging[who]) continue;
			var char = getPreviewCharacter(who);
			if (songPos >= previewActionUntil[who])
			{
				// ถ้า PlayState พาตัวละครกลับ idle เองแล้ว อย่าเรียก dance ซ้ำ (จะสลับ danceLeft/Right ผิดจังหวะ)
				if (char != null && camStartsWith(char.getAnimationName(), 'sing')) danceCharacter(who);
				else previewSinging[who] = false;
			}
			else if (char != null)
				char.holdTimer = 0; // ค้างท่าไว้ตลอดช่วง sustain
		}
	}

	function endManualPreviewHold():Void
	{
		if (manualHeldLane < 0) return;
		if (stageHost != null) try stageHost.callOnScripts('onKeyRelease', [manualHeldLane]) catch (e:Dynamic) trace('Camera Editor onKeyRelease: $e');
		if (manualHeldCharacter >= 0 && manualHeldCharacter < previewSinging.length)
		{
			previewSinging[manualHeldCharacter] = false;
			danceCharacter(manualHeldCharacter);
		}
		manualHeldLane = -1;
		manualHeldCharacter = -1;
	}

	function updatePreviewAnimations(previousTime:Float):Void
	{
		if (previewNotes.length == 0 || PlayState.SONG == null)
		{
			for (who in 0...3)
			{
				var char = getPreviewCharacter(who);
				if (previewSinging[who] && songPos >= previewActionUntil[who])
					danceCharacter(who);
				else if (previewSinging[who] && char != null)
					char.holdTimer = 0;
			}
			lastPreviewTime = songPos;
			return;
		}

		// Seeking backwards (or jumping far in the timeline) reconstructs the pose at that time.
		if (songPos < previousTime || Math.abs(songPos - previousTime) > 1000)
			rebuildPreviewAnimationsAt(songPos);
		else
		{
			while (previewNoteCursor + 1 < previewNotes.length && previewNotes[previewNoteCursor + 1].time <= songPos)
			{
				previewNoteCursor++;
				var n = previewNotes[previewNoteCursor];
				if (isPreviewNoteBlocked(n)) continue;
				playPreviewAnimation(n.who, n.animation, true, previewNoteUntil(n));
			}
		}

		for (who in 0...3)
		{
			var char = getPreviewCharacter(who);
			if (previewSinging[who] && songPos >= previewActionUntil[who])
				danceCharacter(who);
			else if (previewSinging[who] && char != null)
				// Character.update() times out non-player sing animations on its own.
				// Reset its timer while a chart sustain or manual key hold is still active.
				char.holdTimer = 0;
		}

		var beatTick:Int = Conductor.getBeatRounded(songPos);
		if (beatTick != lastBeatTick && songPos >= previousTime)
		{
			lastBeatTick = beatTick;
			for (who in 0...3)
			{
				var char = getPreviewCharacter(who);
				if (char == null || previewSinging[who] || char.stunned || char.specialAnim || camStartsWith(char.getAnimationName(), 'sing')) continue;
				var danceEvery = char.danceEveryNumBeats;
				if (who == 2 && stageHost != null)
					danceEvery = Std.int(Math.max(1, Math.round(stageHost.gfSpeed * danceEvery)));
				if (beatTick % Math.max(1, danceEvery) == 0)
					danceCharacter(who);
			}
		}
	}

	function handleKeys()
	{
		var k = FlxG.keys;
		if (saveConfirmOpen)
		{
			if (k.justPressed.ESCAPE || k.justPressed.N) closeSaveConfirmation();
			else if (k.justPressed.ENTER || k.justPressed.Y) confirmSaveOverwrite();
			return;
		}
		if (suppressInputEnterShortcut)
		{
			suppressInputEnterShortcut = false;
			if (PsychUIInputText.focusOn != null && (k.justPressed.ENTER || k.justPressed.ESCAPE)) PsychUIInputText.focusOn = null;
			return; // The key was for the numeric field, not the editor command layer.
		}
		if (PsychUIInputText.focusOn != null)
		{
			if (k.justPressed.ESCAPE || k.justPressed.ENTER) PsychUIInputText.focusOn = null;
			return;
		}
		if (k.justPressed.F1)
		{
			helpOpen = !helpOpen;
			activeMenu = null;
			if (helpOpen && eventPickerOpen) closeChartEventPicker();
			if (helpOpen) layoutHelp();
			return;
		}
		if (helpOpen)
		{
			if (k.justPressed.ESCAPE) helpOpen = false;
			return;
		}
		if (eventPickerOpen)
		{
			if (k.justPressed.UP) moveChartEventPickerSelection(-1);
			if (k.justPressed.DOWN) moveChartEventPickerSelection(1);
			if (k.justPressed.PAGEUP) moveChartEventPickerSelection(-eventPickerRows.length);
			if (k.justPressed.PAGEDOWN) moveChartEventPickerSelection(eventPickerRows.length);
			if (k.justPressed.ENTER) placeSelectedChartEvent();
			if (k.justPressed.ESCAPE) closeChartEventPicker();
			return;
		}
		if (ddOpen)
		{
			if (k.justPressed.ESCAPE) ddOpen = false;
			return;
		}
		if (kwOpen && (k.justPressed.ESCAPE || k.justPressed.ENTER || k.justPressed.F2))
		{
			closeKeyWindow();
			return;
		}
		var ctrl = k.pressed.CONTROL;

		if (ctrl && k.justPressed.Z)
		{
			if (k.pressed.SHIFT) redo();
			else undo();
		}
		if (ctrl && k.justPressed.Y)
			redo();
		if (ctrl && k.justPressed.S)
			save();
		if (ctrl && k.justPressed.L)
			load();
		var generalSelected = selected != null && selected.track == 'general';
		if (!generalSelected)
		{
			if (k.justPressed.ONE) previewChar = 0;
			if (k.justPressed.TWO) previewChar = 1;
			if (k.justPressed.THREE) previewChar = 2;
		}
		if (k.justPressed.V && !ctrl) setRelativeView(!relativeView);
		if (k.justPressed.B) extendedBounds = !extendedBounds;
		if (k.justPressed.P) passepartout = !passepartout;
		if (k.justPressed.F) fitPreview();
		if (k.justPressed.SPACE)
			togglePlay();
		if (k.justPressed.F5)
			playTest();
		if (k.justPressed.ESCAPE)
		{
			if (activeMenu != null) activeMenu = null;
			else exitEditor();
		}
		if (k.justPressed.S && !ctrl)
		{
			snapEnabled = !snapEnabled;
			status('Snap ' + (snapEnabled ? 'On (ล็อกตาม Step)' : 'Off'));
		}
		if (ctrl && k.justPressed.A) selectAllEvents();
		if (ctrl && k.justPressed.C) copySelection();
		if (ctrl && k.justPressed.V) pasteClipboard();
		if (k.justPressed.DELETE)
		{
			if (multiSel.length > 0) removeMany(multiSel.copy());
			else if (selected != null && selectedChartSource == null) removeEvent(selected);
		}

		if ((k.justPressed.ENTER || k.justPressed.F2) && !ctrl && keyWindowSupported())
			openKeyWindow();

		if (selected == null || ctrl)
			return;

		var old = copyEv(selected);
		var step:Float = k.pressed.SHIFT ? 10 : (k.pressed.ALT ? 0.1 : 1);
		if (selected.track == 'general')
		{
			// General Camera: 1/2/3 = BF/Opponent/GF, T = วนตัวละคร
			if (k.justPressed.ONE) selected.target = 0;
			if (k.justPressed.TWO) selected.target = 1;
			if (k.justPressed.THREE) selected.target = 2;
			if (k.justPressed.T) selected.target = (selected.target + 1) % 3;
			if (selected.target < 0 || selected.target > 2) selected.target = 0;
			selected.x = selected.y = 0;
			selected.duration = 0;
			commitEdit(selected, old);
			previewKey(selected);
			return;
		}
		if (selected.track == "focus")
		{
			var positionChanged = k.justPressed.LEFT || k.justPressed.RIGHT || k.justPressed.UP || k.justPressed.DOWN;
			if (positionChanged && selectedChartSource != null
				&& (selectedChartSource.name.toLowerCase() == 'focuscamera' || selectedChartSource.name.toLowerCase() == 'focus camera') && selected.target >= 0)
			{
				var absolute = resolveXY(selected);
				selected.target = -1;
				selected.x = absolute[0];
				selected.y = absolute[1];
			}
			if (k.justPressed.LEFT) selected.x -= step;
			if (k.justPressed.RIGHT) selected.x += step;
			if (k.justPressed.UP) selected.y -= step;
			if (k.justPressed.DOWN) selected.y += step;
			if (k.justPressed.T)
			{
				var cur = resolveXY(selected);
				selected.target = (selected.target + 2) % 4 - 1; // -1 -> 0 -> 1 -> 2 -> -1
				if (selected.target >= 0)
					selected.x = selected.y = 0;
				else
				{
					selected.x = cur[0];
					selected.y = cur[1];
				}
			}
		}
		else if (selected.track == 'tilt')
		{
			var tiltStep:Float = k.pressed.SHIFT ? 15 : 5;
			if (k.justPressed.Q) selected.angle = angleOf(selected) - tiltStep;
			if (k.justPressed.E) selected.angle = angleOf(selected) + tiltStep;
		}
		else
		{
			var zoomStep:Float = k.pressed.SHIFT ? 0.05 : (k.pressed.ALT ? 0.001 : 0.01);
			if (k.justPressed.Q) selected.zoom = Math.max(0.01, selected.zoom - zoomStep);
			if (k.justPressed.E) selected.zoom = Math.min(5, selected.zoom + zoomStep);
		}
		if (k.justPressed.Z) selected.duration = Math.max(0, selected.duration - 50);
		if (k.justPressed.X) selected.duration = Math.min(Math.max(0, songLen - selected.time), selected.duration + 50);
		if (k.justPressed.C)
			selected.ease = EASES[(EASES.indexOf(selected.ease) + 1) % EASES.length];

		commitEdit(selected, old);
		previewKey(selected);
	}

	function handleMouse()
	{
		if (saveConfirmOpen)
		{
			var cmx = FlxG.mouse.gameX, cmy = FlxG.mouse.gameY;
			if (FlxG.mouse.justPressed)
			{
				if (inRect(cmx, cmy, saveConfirmX + 270, saveConfirmY + 140, 160, 38)) confirmSaveOverwrite();
				else if (inRect(cmx, cmy, saveConfirmX + 430, saveConfirmY + 140, 110, 38)) closeSaveConfirmation();
			}
			return;
		}
		// screenX/screenY are deprecated and remain zero in the current Flixel version.
		// gameX/gameY match the full-screen editor UI coordinates regardless of camera zoom.
		var mx = FlxG.mouse.gameX, my = FlxG.mouse.gameY;
		if (helpOpen)
		{
			if (FlxG.mouse.justPressed && !inRect(mx, my, helpX, helpY, helpPanelW, helpPanelH)) helpOpen = false;
			return;
		}
		if (eventPickerOpen)
		{
			var pickerX = PREV_X + (PREV_W - 700) * 0.5;
			var pickerY = Math.max(8, Math.min(FlxG.height - 368, PREV_Y + (previewPanelHeight() - 360) * 0.5));
			if (FlxG.mouse.wheel != 0 && inRect(mx, my, pickerX, pickerY, 700, 360))
			{
				var maxScroll = Std.int(Math.max(0, availableChartEvents.length - eventPickerRows.length));
				eventPickerScroll = Std.int(Math.max(0, Math.min(maxScroll, eventPickerScroll - FlxG.mouse.wheel)));
				eventPickerIndex = Std.int(Math.max(eventPickerScroll, Math.min(eventPickerIndex, eventPickerScroll + eventPickerRows.length - 1)));
			}
			if (FlxG.mouse.justPressed)
			{
				if (inRect(mx, my, pickerX + 12, pickerY + 48, 326, eventPickerRows.length * 30))
				{
					var row = Std.int((my - pickerY - 48) / 30);
					var pickedIndex = eventPickerScroll + row;
					if (pickedIndex >= 0 && pickedIndex < availableChartEvents.length)
					{
						eventPickerIndex = pickedIndex;
						placeSelectedChartEvent();
					}
					return;
				}
				if (!inRect(mx, my, pickerX, pickerY, 700, 360)) closeChartEventPicker();
				return;
			}
			return;
		}

		if (handleDropdownMouse(mx, my)) return;
		if (kwOpen && handleKeyWindowMouse(mx, my)) return;

		// Compact auto-follow selector lives beside curStep, outside the timeline tracks.
		if (FlxG.mouse.justPressed && mode == None)
		{
			var followRect = timelineFollowButtonRect();
			if (inRect(mx, my, followRect.x, followRect.y, followRect.w, followRect.h))
			{
				cycleTimelineFollow(FlxG.mouse.pressedRight ? -1 : 1);
				return;
			}
		}

		// File/Edit/View menus behave like a small desktop editor menu bar.
		if (FlxG.mouse.justPressed)
		{
			if (activeMenu != null)
			{
				var open = getMenu(activeMenu);
				if (open != null)
				{
					var menuW = menuDropdownWidth(activeMenu);
					var menuX = menuDropdownX(activeMenu);
					if (inRect(mx, my, menuX, 32, menuW, open.items.length * 24 + 8))
					{
						var row = Std.int((my - 36) / 24);
						if (row >= 0 && row < open.items.length)
						{
							var item = open.items[row];
							var action = item.enabled == false ? null : item.action;
							activeMenu = null;
							if (action != null) action();
							return;
					}
					}
				}
				for (b in buttons)
					if (inRect(mx, my, b.txt.x - 8, 4, b.txt.width + 16, 24))
					{
						b.fn();
						return;
					}
				activeMenu = null;
			}
			for (b in buttons)
				if (inRect(mx, my, b.txt.x - 8, 4, b.txt.width + 16, 24))
				{
					b.fn();
					return;
				}
			if (playButton != null && inRect(mx, my, playButton.x - 4, 4, 72, 24))
			{
				togglePlay();
				return;
			}
			if (stopButton != null && inRect(mx, my, stopButton.x - 4, 4, 62, 24))
			{
				stopPreview();
				return;
			}
		}

		handlePropertiesMouse(mx, my);

		rebuildCameraEventList();
		var eventListY = PREV_Y + 38;
		var eventListH = cameraEventRows.length * 28;
		if (FlxG.mouse.wheel != 0 && inRect(mx, my, PANEL_X, eventListY, PANEL_W, eventListH))
		{
			var maxScroll = Std.int(Math.max(0, cameraEventList.length - cameraEventRows.length));
			cameraEventListScroll = Std.int(Math.max(0, Math.min(maxScroll, cameraEventListScroll - FlxG.mouse.wheel)));
		}
		if (FlxG.mouse.justPressed && inRect(mx, my, PANEL_X, eventListY, PANEL_W, eventListH))
		{
			var row = Std.int((my - PREV_Y - 42) / 28);
			var entryIndex = cameraEventListScroll + row;
			if (row >= 0 && row < cameraEventRows.length && entryIndex >= 0 && entryIndex < cameraEventList.length)
				selectCameraListEntry(cameraEventList[entryIndex]);
			return;
		}

		if (FlxG.mouse.justPressed && mode == None && mx < TL_X && my >= timelineTopY + RULER_H && my < timelineTopY + tlHeight() && handleLayerButtons(mx, my))
			return;

		if (FlxG.mouse.justPressed && mode == None && inRect(mx, my, 0, timelineTopY, TL_X, RULER_H) && handleZoomButtons(mx, my))
			return;

		if (FlxG.mouse.justPressed && mode == None && maxLayerScroll() > 0)
		{
			var vt = vScrollTrack();
			if (inRect(mx, my, vt.x - 2, vt.y, vt.w + 4, vt.h))
			{
				var thumbY = vScrollThumbY();
				var thumbH = vScrollThumbH();
				vScrollGrab = my >= thumbY && my <= thumbY + thumbH ? my - thumbY : thumbH * 0.5;
				mode = VScroll;
				setVScroll(my);
				return;
			}
		}
		if (FlxG.mouse.justPressed && mode == None)
		{
			var zs = zoomSliderRect();
			if (inRect(mx, my, zs.x, zs.y, zs.w, zs.h))
			{
				mode = ZoomSlide;
				setZoomFromSlider(mx);
				return;
			}
		}

		// Resize grips have priority over timeline input. A left click on a grip captures
		// the pointer until release, so a missed/partial drag can never drop a chart event.
		// The top grip's hit zone is wider/taller than the tiny visible handle, but reaches
		// only 4px into the ruler (not the event rows).
		var topGrip = timelineTopGripRect();
		if (mode == None && inRect(mx, my, topGrip.x, topGrip.y, topGrip.w, topGrip.h))
		{
			if (FlxG.mouse.justPressed)
			{
				mode = TimelineTopResize;
				timelineTopResizeMouseY = my;
				timelineTopResizeStartY = timelineTopY;
				return;
			}
			// Right-clicking the handle is consumed instead of accidentally placing a key.
			if (FlxG.mouse.justPressedRight) return;
		}

		// Bottom grip is in a dedicated status gutter below TL_BOTTOM, never over the last row.
		var bottomGrip = timelineBottomGripRect();
		if (mode == None && inRect(mx, my, bottomGrip.x, bottomGrip.y, bottomGrip.w, bottomGrip.h))
		{
			if (FlxG.mouse.justPressed)
			{
				mode = TimelineResize;
				timelineResizeMouseY = my;
				timelineResizeStartHeight = timelinePanelHeight;
				return;
			}
			if (FlxG.mouse.justPressedRight) return;
		}

		var inTimeline = inRect(mx, my, TL_X, timelineTopY, FlxG.width - TL_X, tlHeight());
		var inPreview = inRect(mx, my, pvX, pvY, pvW, pvH);
		if (FlxG.mouse.wheel != 0 && inTimeline)
		{
			if (FlxG.keys.pressed.CONTROL)
			{
				// Ctrl + ล้อ = เลื่อนดูเลเยอร์ขึ้น-ลง เมื่อมีเลเยอร์ล้นหน้าจอ
				layerScrollY -= FlxG.mouse.wheel * rowH();
				clampLayerScroll();
			}
			else if (FlxG.keys.pressed.SHIFT)
			{
				var anchor = timeAt(mx);
				pps = Math.max(14, Math.min(600, pps * Math.pow(1.1, FlxG.mouse.wheel)));
				scrollMs = Math.max(0, anchor - (mx - TL_X) / pps * 1000);
				clampTimelineScroll();
			}
			else
			{
				scrollMs = Math.max(0, scrollMs - FlxG.mouse.wheel * 150 / pps * 1000);
				clampTimelineScroll();
			}
		}
		else if (FlxG.mouse.wheel != 0 && inPreview)
		{
			if (FlxG.keys.pressed.SHIFT && selected != null && selected.track == 'zoom')
			{
				var oldZoom = copyEv(selected);
				var zoomStep:Float = FlxG.keys.pressed.ALT ? 0.001 : 0.01;
				selected.zoom = Math.max(0.01, Math.min(5, selected.zoom + FlxG.mouse.wheel * zoomStep));
				commitEdit(selected, oldZoom);
			}
			else if (FlxG.keys.pressed.SHIFT && selected != null && selected.track == 'tilt')
			{
				var oldTilt = copyEv(selected);
				selected.angle = angleOf(selected) + FlxG.mouse.wheel * 2;
				commitEdit(selected, oldTilt);
			}
			else
			{
				// Invert FlxCamera's center-anchored zoom transform so zooming keeps
				// the same point under the cursor at every preview scale.
				var localX = mx - pvX;
				var localY = my - pvY;
				var worldX = viewCenterX + (localX - pvW * 0.5) / previewScale();
				var worldY = viewCenterY + (localY - pvH * 0.5) / previewScale();
				viewZoom = Math.max(0.05, Math.min(12, viewZoom * Math.pow(1.12, FlxG.mouse.wheel)));
				var nextScale = previewScale();
				if (!relativeView)
				{
					// Free View: ซูมโดยให้จุดใต้เมาส์อยู่ที่เดิม (Relative ซูมรอบ VCam)
					viewCenterX = worldX + (pvW * 0.5 - localX) / nextScale;
					viewCenterY = worldY + (pvH * 0.5 - localY) / nextScale;
				}
			}
		}

		if (FlxG.mouse.justPressedMiddle)
		{
			if (inTimeline)
			{
				mode = PanTimeline;
				timelinePanMouseY = my;
				timelinePanOriginY = layerScrollY;
				timelinePanMouseX = mx;
				timelinePanOriginMs = scrollMs;
			}
			else if (inPreview)
			{
				mode = PanPreview;
				previewPanMouseX = mx;
				previewPanMouseY = my;
				setRelativeView(false);
				previewPanOriginX = viewCenterX;
				previewPanOriginY = viewCenterY;
			}
		}
		if (FlxG.mouse.justPressedRight && inPreview && mode == None)
		{
			mode = PanPreview;
			previewPanMouseX = mx;
			previewPanMouseY = my;
			setRelativeView(false);
			previewPanOriginX = viewCenterX;
			previewPanOriginY = viewCenterY;
		}

		// เพิ่ม event ด้วยคลิกขวา
		if (FlxG.mouse.justPressedRight && mx >= TL_X && mode == None)
		{
			var row = rowAt(my);
			if (row != null)
			{
				var t = Math.max(0, snap(timeAt(mx)));
				t = Math.min(songLen, t);
				var cam = evalAt(t);
				if (row.track == 'general')
				{
					// วาง General Camera key: กล้องหันไปหาตัวละครที่เกมจะหันให้ ณ จุดนั้น (แก้ได้ด้วย 1/2/3 หรือ T)
					var si = sectionIndexAt(t);
					var who = si >= 0 ? sectionWho[si] : 0;
					addEvent({time: t, track: 'general', x: 0, y: 0, zoom: cam.zoom, duration: 0, ease: 'linear', target: who, layer: 0});
					status('วาง General Camera -> ${whoName(who)} ที่ ${fmtTime(t)} (1/2/3 เปลี่ยนตัวละคร, Delete ลบ)');
				}
				else
				{
					var tiltRow = row.track == 'tilt';
					addEvent({
						time: t, track: row.track, x: cam.x, y: cam.y, zoom: cam.zoom,
						duration: Math.min(tiltRow ? 1000 : 500, Math.max(0, songLen - t)), ease: tiltRow ? "quadInOut" : "quadOut", target: -1, layer: row.layer,
						angle: tiltRow ? evalAngleAt(t) : 0
					});
				}
			}
		}

		// ดับเบิลคลิก key บน timeline = เปิดหน้าต่างแก้ไข (พิมพ์ตัวเลข / dropdown / กราฟ Ease / Warp / Release)
		if (FlxG.mouse.justPressed && mode == None && inTimeline && my >= timelineTopY + RULER_H)
		{
			var dh = hit(mx, my);
			var nowMs = haxe.Timer.stamp() * 1000;
			if (dh != null && dh == selected && dh == kwLastClickEv && nowMs - kwLastClickMs < 380 && dh.track != 'kick')
			{
				kwLastClickEv = null;
				openKeyWindow();
				return;
			}
			kwLastClickEv = dh;
			kwLastClickMs = nowMs;
		}

		if (FlxG.mouse.justPressed && mode == None)
		{
			if (inTimeline)
			{
				var h = hit(mx, my);
				var autoSec = my >= timelineTopY + RULER_H && h == null ? hitAutoSection(mx, my) : -1;
				if (autoSec >= 0)
				{
					// คลิกช่องอัตโนมัติ = แปลงเป็น General key ของเราเอง จากนั้นแก้/ลบ/ย้ายได้อิสระ
					var who = sectionWho[autoSec];
					addEvent({
						time: sectionCameraTargets[autoSec].time, track: 'general', x: 0, y: 0, zoom: evalAt(sectionCameraTargets[autoSec].time).zoom,
						duration: 0, ease: 'linear', target: who, layer: 0
					});
					status('General Camera: ${whoName(who)} (1/2/3 เปลี่ยนตัวละคร, ลากย้าย, Delete ลบ)');
				}
				else if (my >= timelineTopY + RULER_H && h == null && Math.abs(mx - xAt(songPos)) > 5)
				{
					// ลากบนพื้นที่ว่างของแถว = กรอบเลือกหลายรายการ (คลิกเฉย ๆ = ย้าย playhead)
					mode = Marquee;
					marqueeX0 = mx;
					marqueeY0 = my;
					marqueeAdd = FlxG.keys.pressed.SHIFT || FlxG.keys.pressed.CONTROL;
				}
				else if (my < timelineTopY + RULER_H || h == null)
				{
					multiSel = [];
					selected = h;
					selectedChartSource = h == null ? null : sourceForChartCamera(h);
					refreshEventValueInputs();
					mode = Seek;
					resumeAfterSeek = playing;
					if (playing) setPlayback(false);
				}
				else if ((FlxG.keys.pressed.SHIFT || FlxG.keys.pressed.CONTROL) && events.indexOf(h) >= 0)
				{
					// Shift/Ctrl + คลิก = เพิ่ม/เอาออกจากชุดที่เลือก (Multi-selection)
					if (multiSel.length == 0 && selected != null && selected != h && events.indexOf(selected) >= 0) multiSel.push(selected);
					if (multiSel.indexOf(h) >= 0) multiSel.remove(h);
					else multiSel.push(h);
					selected = h;
					selectedChartSource = null;
					selectedChartComponent = null;
					refreshEventValueInputs();
					status('เลือก ${multiSel.length} events');
				}
				else
				{
					selected = h;
					selectedChartSource = sourceForChartCamera(h);
					refreshEventValueInputs();
					previewKey(h);
					dragEv = h;
					dragOld = copyEv(h);
					dragOffset = timeAt(mx) - h.time;
					var blockW = Math.max(16, h.duration * pps / 1000);
					var right = xAt(h.time) + blockW;
					mode = (h.track != 'general' && mx >= right - Math.min(EDGE, blockW * 0.5)) ? Resize : Move;
					dragMulti = null;
					if (mode == Move && multiSel.length > 1 && multiSel.indexOf(h) >= 0)
					{
						dragMulti = multiSel.copy();
						dragMultiOld = [for (e in dragMulti) copyEv(e)];
					}
					else if (multiSel.indexOf(h) < 0) multiSel = [];
				}
			}
			else if (inPreview && FlxG.keys.pressed.ALT)
			{
				// Alt + ลากซ้าย = เลื่อนจอ (เหมือนปุ่มกลาง / คลิกขวา)
				mode = PanPreview;
				previewPanMouseX = mx;
				previewPanMouseY = my;
				setRelativeView(false);
				previewPanOriginX = viewCenterX;
				previewPanOriginY = viewCenterY;
			}
			else if (inPreview)
			{
				// ลากใน viewport เพื่อแก้ Focus event; ถ้ายังไม่มี Focus key ที่เลือกอยู่ จะสร้างให้ "ตอนที่ลากจริง"
				// (คลิกเฉย ๆ ไม่ทิ้ง key เปล่า ๆ และการสร้าง+ย้ายนับเป็น Undo สเต็ปเดียว)
				previewDragMouseX = mx;
				previewDragMouseY = my;
				previewDragZoom = previewScale();
				dragCreated = false;
				if (selected != null && selected.track == "focus")
				{
					dragEv = selected;
					dragOld = copyEv(selected);
					var origin = resolveXY(selected);
					previewDragOriginX = origin[0];
					previewDragOriginY = origin[1];
				}
				else
				{
					dragEv = null;
					dragOld = null;
					var camNow = evalAt(songPos);
					previewDragOriginX = camNow.x;
					previewDragOriginY = camNow.y;
				}
				mode = Preview;
			}
		}

		if ((FlxG.mouse.pressed || FlxG.mouse.pressedMiddle || FlxG.mouse.pressedRight) && mode != None)
		{
			switch (mode)
			{
				case Seek:
					seekTo(timeAt(mx));
				case Move:
					dragEv.time = Math.max(0, Math.min(Math.max(0, songLen - dragEv.duration), snap(timeAt(mx) - dragOffset)));
					if (dragMulti != null)
					{
						// ย้ายทั้งชุดด้วยระยะเท่ากัน (ไม่ให้หลุดต้นเพลง/ท้ายเพลง)
						var delta = dragEv.time - dragOld.time;
						var lo = Math.NEGATIVE_INFINITY, hi = Math.POSITIVE_INFINITY;
						for (o in dragMultiOld)
						{
							lo = Math.max(lo, -o.time);
							hi = Math.min(hi, songLen - o.time - o.duration);
						}
						delta = Math.max(lo, Math.min(Math.max(lo, hi), delta));
						for (i in 0...dragMulti.length) dragMulti[i].time = dragMultiOld[i].time + delta;
					}
					else if (selectedChartSource == null)
					{
						// ลากขึ้น/ลงเพื่อย้ายข้ามเลเยอร์ (ภายใน track เดิมเท่านั้น)
						var moveRow = rowAt(my);
						if (moveRow != null && moveRow.track == dragEv.track) dragEv.layer = moveRow.layer;
					}
				case Resize:
					dragEv.duration = Math.max(0, Math.min(songLen - dragEv.time, snap(timeAt(mx)) - dragEv.time));
				case Preview:
					if (dragEv == null && Math.abs(mx - previewDragMouseX) + Math.abs(my - previewDragMouseY) >= 4)
					{
						var camNow = evalAt(songPos);
						var newEv:CamEvent = {
							time: songPos, track: "focus", x: previewDragOriginX, y: previewDragOriginY, zoom: camNow.zoom,
							duration: 500, ease: "quadOut", target: -1, layer: freeLayer("focus", songPos, 500)
						};
						newEv.time = Math.max(0, Math.min(songLen, newEv.time));
						newEv.duration = Math.max(0, Math.min(songLen - newEv.time, newEv.duration));
						events.push(newEv);
						sortEvents();
						selected = newEv;
						selectedChartSource = null;
						selectedChartComponent = null;
						refreshEventValueInputs();
						dragEv = newEv;
						dragOld = copyEv(newEv);
						dragCreated = true;
					}
					if (dragEv != null)
					{
						// Translate screen delta into world units using the actual preview zoom.
						var z = previewDragZoom > 0 ? previewDragZoom : 1;
						dragEv.target = -1;
						var dragDX = mx - previewDragMouseX;
						var dragDY = my - previewDragMouseY;
						if (relativeView && Math.abs(vcamAngle) > 0.05)
						{
							// ฉากหมุนตามกล้องที่เอียง: หมุนระยะที่ลากกลับให้เป็นระยะในโลกจริง
							var unrotDrag = -vcamAngle * Math.PI / 180;
							var rdx = dragDX * Math.cos(unrotDrag) - dragDY * Math.sin(unrotDrag);
							var rdy = dragDX * Math.sin(unrotDrag) + dragDY * Math.cos(unrotDrag);
							dragDX = rdx;
							dragDY = rdy;
						}
						var dragSensitivity:Float = FlxG.keys.pressed.ALT ? 0.1 : (FlxG.keys.pressed.SHIFT ? 5 : 1);
						dragEv.x = Math.round((previewDragOriginX + dragDX / z * dragSensitivity) * 10) / 10;
						dragEv.y = Math.round((previewDragOriginY + dragDY / z * dragSensitivity) * 10) / 10;
					}
				case PanTimeline:
					scrollMs = Math.max(0, timelinePanOriginMs - (mx - timelinePanMouseX) / pps * 1000);
					clampTimelineScroll();
					layerScrollY = timelinePanOriginY - (my - timelinePanMouseY);
					clampLayerScroll();
				case TimelineResize:
					timelinePanelHeight = Math.max(RULER_H + rowH(), Math.min(TL_BOTTOM - timelineTopY, timelineResizeStartHeight + (my - timelineResizeMouseY)));
					clampLayerScroll();
				case TimelineTopResize:
					var minTop = PREV_Y + MIN_PREVIEW_PANEL_H + PREVIEW_TIMELINE_GAP;
					var maxTop = TL_BOTTOM - (RULER_H + rowH());
					timelineTopY = Std.int(Math.max(minTop, Math.min(maxTop, timelineTopResizeStartY + (my - timelineTopResizeMouseY))));
					timelinePanelHeight = TL_BOTTOM - timelineTopY;
					computePreviewViewport();
					fitPreviewEventVideo(previewEventVideo);
					clampLayerScroll();
				case Marquee:
				case ZoomSlide:
					setZoomFromSlider(mx);
				case VScroll:
					setVScroll(my);
				case PropSlide:
					setPropSliderFromMouse(mx);
				case PanPreview:
					var z = previewScale();
					viewCenterX = previewPanOriginX - (mx - previewPanMouseX) / z;
					viewCenterY = previewPanOriginY - (my - previewPanMouseY) / z;
				case None:
			}
		}

		var released = mode == PanTimeline ? FlxG.mouse.justReleasedMiddle
			: (mode == PanPreview ? (FlxG.mouse.justReleasedMiddle || FlxG.mouse.justReleasedRight || FlxG.mouse.justReleased) : FlxG.mouse.justReleased);
		if (released && mode != None)
		{
			if (mode == Marquee) finishMarquee(mx, my);
			if (mode == Seek)
			{
				seekTo(timeAt(mx));
				if (resumeAfterSeek) setPlayback(true);
				resumeAfterSeek = false;
			}
			if ((mode == Move || mode == Resize || mode == Preview) && dragEv != null)
			{
				if (dragCreated)
				{
					// key ที่สร้างระหว่างลากใน Preview: บันทึกเป็น Undo สเต็ปเดียว (เพิ่ม + ย้าย)
					events.remove(dragEv);
					addEvent(dragEv);
				}
				else if (dragMulti != null)
				{
					sortEvents();
					commitGroupMove(dragMulti, dragMultiOld);
				}
				else
				{
					sortEvents();
					commitEdit(dragEv, dragOld, false);
				}
			}
			dragCreated = false;
			mode = None;
			dragEv = null;
			dragOld = null;
			dragMulti = null;
			dragMultiOld = null;
		}
	}

	/** Load a cursor from the P-Slice embedded UI folder, with filesystem fallback for desktop builds. */
	function loadEditorCursorBitmap(fileName:String):BitmapData
	{
		var paths = [
			'assets/embed/images/ui/' + fileName + '.png',
			'embed/images/ui/' + fileName + '.png',
			'assets/images/ui/' + fileName + '.png'
		];
		for (path in paths)
		{
			try
			{
				if (Assets.exists(path))
				{
					var embedded = Assets.getBitmapData(path);
					if (embedded != null) return embedded;
				}
			}
			catch (e:Dynamic) {}
			#if sys
			try
			{
				if (sys.FileSystem.exists(path))
				{
					var diskBitmap = BitmapData.fromFile(path);
					if (diskBitmap != null) return diskBitmap;
				}
			}
			catch (e:Dynamic) {}
			#end
		}
		return null;
	}

	/** Hand = hover a draggable area; hand2 = actively holding a drag/resize. */
	function updateEditorCursor(mx:Float, my:Float):Void
	{
		var next = 'default';
		if (mode != None && (FlxG.mouse.pressed || FlxG.mouse.pressedMiddle || FlxG.mouse.pressedRight))
			next = 'hand2';
		else
		{
			var topGrip = timelineTopGripRect();
			var bottomGrip = timelineBottomGripRect();
			var overTopGrip = inRect(mx, my, topGrip.x, topGrip.y, topGrip.w, topGrip.h);
			var overBottomGrip = inRect(mx, my, bottomGrip.x, bottomGrip.y, bottomGrip.w, bottomGrip.h);
			var overKey = mx >= TL_X && my >= timelineTopY + RULER_H && my < timelineTopY + tlHeight() && hit(Std.int(mx), Std.int(my)) != null;
			var overPreview = inRect(mx, my, pvX, pvY, pvW, pvH);
			var overSlider = inRect(mx, my, zoomSliderRect().x, zoomSliderRect().y, zoomSliderRect().w, zoomSliderRect().h);
			var overRowsScroll = maxLayerScroll() > 0 && inRect(mx, my, vScrollTrack().x - 2, vScrollTrack().y, vScrollTrack().w + 4, vScrollTrack().h);
			if (overTopGrip || overBottomGrip || overKey || overPreview || overSlider || overRowsScroll)
				next = 'hand';
		}
		if (next == editorCursorState) return;
		editorCursorState = next;
		if (next == 'default')
		{
			if (editorOriginalCursor != null)
				FlxG.mouse.load(editorOriginalCursor, 1, 1, 1);
			else
			{
				if (editorCursorDefault == null) editorCursorDefault = loadEditorCursorBitmap('cursor');
				if (editorCursorDefault == null) editorCursorDefault = loadEditorCursorBitmap('mouse');
				if (editorCursorDefault != null) FlxG.mouse.load(editorCursorDefault, 1, 1, 1); else FlxG.mouse.unload();
			}
		}
		else if (next == 'hand')
		{
			if (editorCursorHand == null) editorCursorHand = loadEditorCursorBitmap('cursorhand');
			if (editorCursorHand != null) FlxG.mouse.load(editorCursorHand, 1, 1, 1); else FlxG.mouse.unload();
		}
		else if (next == 'hand2')
		{
			if (editorCursorHand2 == null) editorCursorHand2 = loadEditorCursorBitmap('cursorhand2');
			if (editorCursorHand2 != null) FlxG.mouse.load(editorCursorHand2, 1, 1, 1); else FlxG.mouse.unload();
		}
		else
			FlxG.mouse.unload();
	}

	// =====================================================================
	//  Drawing
	// =====================================================================
	function rect(x:Float, y:Float, w:Float, h:Float, c:FlxColor)
	{
		c = th(c);
		if (clipOn)
		{
			var y2 = y + h;
			if (y < clipY0) y = clipY0;
			if (y2 > clipY1) y2 = clipY1;
			if (y2 <= y) return;
			h = y2 - y;
		}
		if (c.alpha < 255)
		{
			blendRect(x, y, w, h, c);
			return;
		}
		tmpRect.setTo(x, y, w, h);
		canvas.pixels.fillRect(tmpRect, c);
	}

	/** Source-over blend of a translucent color onto the canvas (fillRect would overwrite and punch see-through holes in the UI). */
	function blendRect(x:Float, y:Float, w:Float, h:Float, c:FlxColor):Void
	{
		var x1 = Math.round(x), y1 = Math.round(y);
		var x2 = Math.round(x + w), y2 = Math.round(y + h);
		if (x2 <= x1 || y2 <= y1 || c.alpha == 0) return;
		if (blendSrc == null) blendSrc = new BitmapData(1, 1, true, 0xFFFFFFFF);
		blendMatrix.setTo(x2 - x1, 0, 0, y2 - y1, x1, y1);
		blendCT.redMultiplier = blendCT.greenMultiplier = blendCT.blueMultiplier = 0;
		blendCT.alphaMultiplier = c.alpha / 255;
		blendCT.redOffset = c.red;
		blendCT.greenOffset = c.green;
		blendCT.blueOffset = c.blue;
		blendCT.alphaOffset = 0;
		tmpRect.setTo(x1, y1, x2 - x1, y2 - y1);
		canvas.pixels.draw(blendSrc, blendMatrix, blendCT, null, tmpRect, false);
	}

	function frameRect(x:Float, y:Float, w:Float, h:Float, c:FlxColor, t:Int = 2)
	{
		rect(x, y, w, t, c);
		rect(x, y + h - t, w, t, c);
		rect(x, y, t, h, c);
		rect(x + w - t, y, t, h, c);
	}

	function clippedCameraFrame(x:Float, y:Float, w:Float, h:Float, color:FlxColor, thickness:Int = 2):Void
	{
		var left = pvX;
		var top = pvY;
		var right = pvX + pvW;
		var bottom = pvY + pvH;
		var x2 = x + w;
		var y2 = y + h;
		if (y >= top && y < bottom) rect(Math.max(left, x), y, Math.max(0, Math.min(right, x2) - Math.max(left, x)), thickness, color);
		if (y2 - thickness >= top && y2 - thickness < bottom) rect(Math.max(left, x), y2 - thickness, Math.max(0, Math.min(right, x2) - Math.max(left, x)), thickness, color);
		if (x >= left && x < right) rect(x, Math.max(top, y), thickness, Math.max(0, Math.min(bottom, y2) - Math.max(top, y)), color);
		if (x2 - thickness >= left && x2 - thickness < right) rect(x2 - thickness, Math.max(top, y), thickness, Math.max(0, Math.min(bottom, y2) - Math.max(top, y)), color);
	}

	function getMenu(name:String):CameraEditorMenu
	{
		for (menu in menus)
			if (menu.name == name) return menu;
		return null;
	}

	function menuHeaderX(name:String):Float
	{
		for (button in buttons)
			if (button.txt.text == name) return button.txt.x - 8;
		return 8;
	}

	function menuDropdownWidth(name:String):Float
		return Math.min(name == 'File' ? 420 : 230, Math.max(0, FlxG.width - 8));

	function menuDropdownX(name:String):Float
	{
		var width = menuDropdownWidth(name);
		return Math.max(4, Math.min(FlxG.width - width - 4, menuHeaderX(name)));
	}

	/** กรอบ VCam ที่หมุนตามมุมกล้อง (Free View): วาดเป็นเส้นจุดต่อกันและตัดให้อยู่ในพรีวิว */
	function rotatedCameraFrame(cx:Float, cy:Float, w:Float, h:Float, angleDeg:Float, color:FlxColor):Void
	{
		var rad = angleDeg * Math.PI / 180;
		var cs = Math.cos(rad), sn = Math.sin(rad);
		var hw = w * 0.5, hh = h * 0.5;
		var xs:Array<Float> = [], ys:Array<Float> = [];
		for (c in [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]])
		{
			xs.push(cx + c[0] * cs - c[1] * sn);
			ys.push(cy + c[0] * sn + c[1] * cs);
		}
		for (i in 0...4)
		{
			var j = (i + 1) % 4;
			var len = Math.sqrt((xs[j] - xs[i]) * (xs[j] - xs[i]) + (ys[j] - ys[i]) * (ys[j] - ys[i]));
			var steps = Std.int(Math.min(4000, Math.ceil(len / 2)));
			for (k in 0...steps + 1)
			{
				var t = steps == 0 ? 0 : k / steps;
				var px = xs[i] + (xs[j] - xs[i]) * t;
				var py = ys[i] + (ys[j] - ys[i]) * t;
				if (inRect(px, py, pvX, pvY, pvW - 2, pvH - 2)) rect(px, py, 2, 2, color);
			}
		}
	}

	function drawPassepartout(x:Float, y:Float, w:Float, h:Float):Void
	{
		var left = pvX;
		var top = pvY;
		var right = pvX + pvW;
		var bottom = pvY + pvH;
		var innerL = Math.max(left, Math.min(right, x));
		var innerT = Math.max(top, Math.min(bottom, y));
		var innerR = Math.max(left, Math.min(right, x + w));
		var innerB = Math.max(top, Math.min(bottom, y + h));
		rect(left, top, pvW, Math.max(0, innerT - top), 0x70000000);
		rect(left, innerB, pvW, Math.max(0, bottom - innerB), 0x70000000);
		rect(left, innerT, Math.max(0, innerL - left), Math.max(0, innerB - innerT), 0x70000000);
		rect(innerR, innerT, Math.max(0, right - innerR), Math.max(0, innerB - innerT), 0x70000000);
	}

	function drawOpenMenu():Void
	{
		var openMenu = getMenu(activeMenu);
		if (openMenu != null)
		{
			var menuW = menuDropdownWidth(activeMenu);
			var menuX = menuDropdownX(activeMenu);
			var menuY = 32;
			var menuH = openMenu.items.length * 24 + 8;
			rect(menuX, menuY, menuW, menuH, 0xFF252A32);
			frameRect(menuX, menuY, menuW, menuH, 0xFF566170, 1);
			for (i in 0...openMenu.items.length)
			{
				var rowY = menuY + 4 + i * 24;
				var itemEnabled = openMenu.items[i].enabled != false;
				if (itemEnabled && inRect(FlxG.mouse.gameX, FlxG.mouse.gameY, menuX + 3, rowY, menuW - 6, 24))
					rect(menuX + 3, rowY, menuW - 6, 24, 0xFF3C566A);
				var itemText = menuItemTexts[i];
				var itemLabel:String = openMenu.items[i].label;
				// Keep every menu action at the same font size and on one fixed-height row.
				if (itemText.size != 12) itemText.size = 12;
				itemText.color = itemEnabled ? th(0xFFE3E8EF) : th(0xFF737B86);
				setTextIfChanged(itemText, itemLabel);
				var toggleState = openMenu.name == 'View' ? viewToggleState(openMenu.items[i].label) : (openMenu.name == 'Theme' ? (openMenu.items[i].label == THEME_NAMES[themeIndex] ? 1 : 0) : -1);
				if (toggleState >= 0)
				{
					drawMenuCheck(menuX + 10, rowY + 6, toggleState == 1);
					itemText.setPosition(menuX + 32, rowY + 4);
				}
				else
					itemText.setPosition(menuX + 12, rowY + 4);
				itemText.visible = true;
			}
		}
	}

	function redraw()
	{
		var px = canvas.pixels;
		tmpRect.setTo(0, 0, px.width, px.height);
		px.fillRect(tmpRect, th(0xFF101720));
		// เจาะช่องโปร่งใสเท่าวิวพอร์ต ให้เห็นฉากจากกล้องเกมเฉพาะในช่องนี้ ส่วนอื่นทั้งหมดถูก UI ปิดไว้
		tmpRect.setTo(pvX, pvY, pvW, pvH);
		px.fillRect(tmpRect, 0x00000000);

		// Clean toolbar, scene viewport, inspector, and timeline surfaces.
		rect(0, 0, FlxG.width, 32, 0xFF17212D);
		rect(0, 31, FlxG.width, 1, 0xFF34475A);
		rect(0, 0, 3, 32, 0xFF52B8C8);
		if (playButton != null)
		{
			setTextIfChanged(playButton, playing ? 'Pause' : 'Play');
			rect(playButton.x - 4, 4, 72, 24, playing ? 0xFF214A55 : 0xFF202D3A);
			frameRect(playButton.x - 4, 4, 72, 24, playing ? 0xFF55BCCD : 0xFF34475A, 1);
		}
		if (stopButton != null)
		{
			rect(stopButton.x - 4, 4, 62, 24, 0xFF202D3A);
			frameRect(stopButton.x - 4, 4, 62, 24, 0xFF34475A, 1);
		}
		for (b in buttons)
		{
			var active = activeMenu == b.txt.text;
			var btnColor:FlxColor = active ? 0xFF244A57 : 0xFF202D3A;
			rect(b.txt.x - 8, 4, b.txt.width + 16, 24, btnColor);
			frameRect(b.txt.x - 8, 4, b.txt.width + 16, 24, active ? 0xFF55BCCD : 0xFF34475A, 1);
		}
		for (itemText in menuItemTexts) itemText.visible = false;
		// ---- Preview viewport frame; stage + characters are the real PlayState scene
		// drawn through camGame. The UI camera draws this border.
		// Keep the preview interior transparent: this UI canvas is drawn after previewCamera.
		// An opaque fill here hides every stage sprite rendered by the preview camera.
		// ส่วนของพื้นที่พรีวิวที่ไม่ใช่ภาพ (วิวพอร์ตมีสัดส่วนเท่าจอเกม) ระบายสีพื้นให้เนียนกับ editor แทนขอบดำ
		rect(PREV_X, PREV_Y, PREV_W, pvY - PREV_Y, 0xFF16191E);
		rect(PREV_X, pvY + pvH, PREV_W, PREV_Y + previewPanelHeight() - (pvY + pvH), 0xFF16191E);
		rect(PREV_X, pvY, pvX - PREV_X, pvH, 0xFF16191E);
		rect(pvX + pvW, pvY, PREV_X + PREV_W - (pvX + pvW), pvH, 0xFF16191E);
		frameRect(pvX, pvY, pvW, pvH, 0xFF48515D, 2);
		// กรอบ VCam = ขอบเขตที่ผู้เล่นเห็นจริง ตาม timeline (ตอนหยุด) หรือกล้องเกมจริง (ตอนเล่น)
		var cam = vcamPose;
		var bounds = cameraFrameRect(cam);
		if (!relativeView)
		{
			// ใช้ shake offset เป็นการขยับกรอบ VCam ใน Free View แทนการเขย่าพรีวิว/แถบ UI ทั้งหน้า
			var shakeScale = previewScale();
			bounds.x += vcamFxShakeX * shakeScale;
			bounds.y += vcamFxShakeY * shakeScale;
			if (!saveConfirmOpen) drawVCamCameraFX(bounds, vcamAngle);
		}
		if (showCameraFrame && !saveConfirmOpen)
		{
			var frameColor:FlxColor = extendedBounds ? 0xFFFFC76B : 0xFF58D1E2;
			if (!relativeView && Math.abs(vcamAngle) > 0.05)
				rotatedCameraFrame(bounds.x + bounds.width * 0.5, bounds.y + bounds.height * 0.5, bounds.width, bounds.height, -vcamAngle, frameColor);
			else
			{
				if (passepartout) drawPassepartout(bounds.x, bounds.y, bounds.width, bounds.height);
				clippedCameraFrame(bounds.x, bounds.y, bounds.width, bounds.height, frameColor, 2);
			}
			var crossX = bounds.x + bounds.width * 0.5;
			var crossY = bounds.y + bounds.height * 0.5;
			if (inRect(crossX, crossY, pvX, pvY, pvW, pvH))
			{
				rect(crossX - 7, crossY, 14, 1, 0xFFECF7FF);
				rect(crossX, crossY - 7, 1, 14, 0xFFECF7FF);
			}
			// event คุมกล้องอยู่: วาดกรอบส้มบางตรงเป้าหมายของ timeline (กล้องจริงกำลังไล่ตามด้วย lerp) cameraFrameRect ใช้ scratch ร่วม จึงวาดหลังสุด
			if (playing && vcamTimelineOwned)
			{
				var ghost = cameraFrameRect(vcamExpected);
				clippedCameraFrame(ghost.x, ghost.y, ghost.width, ghost.height, 0xFFFF9F43, 1);
			}
		}
		if (vcamInfoText != null)
		{
			if (showCameraFrame && !saveConfirmOpen)
			{
				var info = 'VCAM  X ' + Math.round(vcamPose.x) + '  Y ' + Math.round(vcamPose.y) + '  ZOOM ' + (Math.round(vcamPose.zoom * 1000) / 1000);
				if (Math.abs(vcamAngle) > 0.05) info += '  ROT ' + (Math.round(vcamAngle * 10) / 10);
				if (playing && vcamTimelineOwned) info += '  [EVENT]';
				setTextIfChanged(vcamInfoText, info);
				vcamInfoText.color = th(playing && vcamTimelineOwned ? 0xFFFFD9A8 : 0xFFECF7FF);
				vcamInfoText.setPosition(pvX + 8, pvY + pvH - vcamInfoText.height - 6);
				vcamInfoText.visible = true;
			}
			else
				vcamInfoText.visible = false;
		}

		// Properties panel
		rect(PANEL_X, PREV_Y, PANEL_W, previewPanelHeight(), 0xFF1A2430);
		rect(PANEL_X, PREV_Y, PANEL_W, 34, 0xFF222F3D);
		rect(PANEL_X, PREV_Y + 33, PANEL_W, 1, 0xFF3A5064);
		rect(PANEL_X, PREV_Y, 2, previewPanelHeight(), 0xFF3E9EAF);
		rebuildCameraEventList();
		if (cameraEventTitleCount != cameraEventList.length)
		{
			cameraEventTitleCount = cameraEventList.length;
			setTextIfChanged(panelTitle, 'EVENT INSPECTOR  ·  ${cameraEventList.length}');
		}
		for (i in 0...cameraEventRows.length)
		{
			var listIndex = cameraEventListScroll + i;
			var row = cameraEventRows[i];
			if (listIndex >= cameraEventList.length)
			{
				cameraEventVisibleEntries[i] = null;
				if (cameraEventList.length == 0 && i == 0)
				{
					setTextIfChanged(row, 'No chart events');
					row.setPosition(PANEL_X + 14, PREV_Y + 49);
					row.visible = true;
				}
				else row.visible = false;
				continue;
			}
			var entry = cameraEventList[listIndex];
			var rowY = PREV_Y + 42 + i * 28;
			var isSelected = entry.source != null
				? entry.source == selectedChartSource && entry.component == selectedChartComponent && (entry.camera == null || entry.camera == selected)
				: entry.camera != null && entry.camera == selected;
			if (isSelected)
			{
				rect(PANEL_X + 8, rowY, PANEL_W - 16, 25, 0xFF214653);
				rect(PANEL_X + 8, rowY, 2, 25, 0xFF55C4D4);
			}
			else if (i % 2 == 1) rect(PANEL_X + 8, rowY, PANEL_W - 16, 25, 0xFF202B37);
			if (cameraEventVisibleEntries[i] != entry)
			{
				cameraEventVisibleEntries[i] = entry;
				setTextIfChanged(row, '${fmtTime(entry.time)}  ${entry.name}');
			}
			row.setPosition(PANEL_X + 14, rowY + 5);
			row.visible = true;
		}
		rect(PANEL_X + 12, PREV_Y + 219, PANEL_W - 24, 1, 0xFF3A5064);
		// (removed) leftover white bars from the old Value1/Value2 input boxes; they were
		// painted over the Duration / Position Y rows and hid their labels.
		drawPropertiesPanel();

		// ---- timeline ----
		var tlW = FlxG.width - TL_X;
		var rh = rowH();
		var rows = rowCount();
		clampLayerScroll();
		var tlH = tlHeight();
		var pad:Int = Std.int(Math.max(2, Math.round(rh * 6 / 54)));
		rect(0, timelineTopY, FlxG.width, tlH, 0xFF22262D);
		rect(0, timelineTopY, TL_X, tlH, 0xFF2C323B);
		clipOn = true;
		clipY0 = timelineTopY + RULER_H;
		clipY1 = timelineTopY + tlH;
		for (r in 0...rows)
		{
			var focusRow = r < focusLayers;
			var shade:FlxColor = focusRow ? (r % 2 == 0 ? 0xFF292E36 : 0xFF2D323B) : (r % 2 == 0 ? 0xFF242930 : 0xFF282D35);
			var rowTop = timelineTopY + RULER_H + r * rh - Std.int(layerScrollY);
			rect(TL_X, rowTop, tlW, rh, shade);
			rect(TL_X, rowTop, tlW, 1, (r == focusLayers || r == focusLayers + zoomLayers || r == focusLayers + zoomLayers + tiltLayers) ? 0xFF52677C : 0xFF354658);
		}
		clipOn = false;
		rect(TL_X, timelineTopY, tlW, RULER_H, 0xFF343B46);
		for (zi in 0...2)
		{
			var zr = zoomButtonRect(zi == 1);
			rect(zr.x, zr.y, zr.w, zr.h, 0xFF3A4350);
			frameRect(zr.x, zr.y, zr.w, zr.h, 0xFF5D6877, 1);
			var zt = zoomBtnTexts[zi];
			zt.setPosition(zr.x + (zr.w - zt.width) * 0.5, zr.y + (zr.h - zt.height) * 0.5);
			zt.visible = true;
		}
		var zs = zoomSliderRect();
		rect(zs.x, zs.y + 7, zs.w, 2, 0xFF6A7482);
		var zt01 = Math.max(0, Math.min(1, Math.log(pps / 14) / Math.log(600 / 14)));
		rect(zs.x + zt01 * zs.w - 3, zs.y + 1, 6, 14, 0xFFB7C6D6);
		zoomBtnTexts[2].visible = false;

		// ชื่อเลเยอร์ + ปุ่ม + / - ของแต่ละ track
		for (i in 0...layerLabels.length)
		{
			var lt = layerLabels[i];
			if (i >= rows)
			{
				lt.visible = false;
				continue;
			}
			var labelStr:String;
			var swatch:FlxColor;
			if (i < focusLayers)
			{
				labelStr = 'FocusCamera' + (focusLayers > 1 ? ' ' + (i + 1) : '');
				swatch = 0xFF387B88;
			}
			else if (i < focusLayers + zoomLayers)
			{
				labelStr = 'ZoomCamera' + (zoomLayers > 1 ? ' ' + (i - focusLayers + 1) : '');
				swatch = 0xFF6651A2;
			}
			else if (i < focusLayers + zoomLayers + tiltLayers)
			{
				labelStr = 'TiltCamera' + (tiltLayers > 1 ? ' ' + (i - focusLayers - zoomLayers + 1) : '');
				swatch = 0xFF3E8F5A;
			}
			else
			{
				labelStr = 'GeneralCamera';
				swatch = 0xFFB05A9A;
			}
			setTextIfChanged(lt, labelStr);
			var swY = timelineTopY + RULER_H + i * rh - Std.int(layerScrollY) + (rh - 12) * 0.5;
			clipOn = true;
			clipY0 = timelineTopY + RULER_H;
			clipY1 = timelineTopY + tlH;
			rect(8, swY, 12, 12, swatch);
			clipOn = false;
			var labelY = timelineTopY + RULER_H + i * rh - Std.int(layerScrollY) + Math.max(0, (rh - lt.height) * 0.5);
			lt.setPosition(26, labelY);
			lt.visible = labelY >= timelineTopY + RULER_H && labelY + lt.height <= timelineTopY + tlH;
		}
		for (g in 0...3)
			for (m in 0...2)
			{
				var br = layerButtonRect(g, m == 1);
				var bt = layerButtons[g * 2 + m];
				if (br.h <= 0)
				{
					bt.visible = false;
					continue;
				}
				rect(br.x, br.y, br.w, br.h, 0xFF3A4350);
				frameRect(br.x, br.y, br.w, br.h, 0xFF5D6877, 1);
				bt.setPosition(br.x + (br.w - bt.width) * 0.5, br.y + (br.h - bt.height) * 0.5 - 1);
				bt.visible = true;
			}

		// Beat / step ruler with bar numbers; tempo changes follow Conductor's BPM map.
		var firstBeat = Std.int(Math.floor(Math.max(0, Conductor.getBeat(Math.min(songLen, scrollMs))))) - 1;
		var lastBeat = Std.int(Math.ceil(Conductor.getBeat(timeAt(FlxG.width)))) + 1;
		var ti = 0;
		for (beat in firstBeat...(lastBeat + 1))
		{
			if (beat < 0) continue;
			var beatTime = Conductor.beatToSeconds(beat);
			if (beatTime > songLen) continue;
			var x = xAt(beatTime);
			if (x >= TL_X && x < FlxG.width)
			{
				// เลข Section จริงจาก Chart (รองรับ Section ที่ไม่ใช่ 4 บีต); ไม่มี Chart ใช้ทุก 4 บีต
				var secNo = -1;
				if (sectionCameraTargets.length > 0)
				{
					for (si in 0...sectionCameraTargets.length)
						if (Math.abs(sectionCameraTargets[si].time - beatTime) < 2)
						{
							secNo = si + 1;
							break;
						}
				}
				else if (beat % 4 == 0) secNo = Std.int(beat / 4) + 1;
				var bar = secNo > 0;
				rect(x, timelineTopY + (bar ? 4 : 12), 1, tlH - (bar ? 4 : 12), bar ? 0xFF59616D : 0xFF39414C);
				if (bar && ti < rulerTexts.length)
				{
					setTextIfChanged(rulerTexts[ti], Std.string(secNo)); // หมายเลข Section (measure)
					rulerTexts[ti].x = x + 3;
					rulerTexts[ti].y = timelineTopY + 1;
					rulerTexts[ti].visible = true;
					ti++;
				}
				var stepTime = Conductor.beatToSeconds(beat + 0.25);
				var stepX = xAt(stepTime);
				if (stepTime <= songLen && stepX - x >= 4)
					for (step in 1...4)
					{
						var stepBeatTime = Conductor.beatToSeconds(beat + step * 0.25);
						if (stepBeatTime <= songLen)
						{
							var sx = xAt(stepBeatTime);
							rect(sx, timelineTopY + RULER_H - 5, 1, 4, 0xFF69727F);
						}
					}
			}
		}
		for (i in ti...rulerTexts.length)
			rulerTexts[i].visible = false;

		clipOn = true;
		clipY0 = timelineTopY + RULER_H;
		clipY1 = timelineTopY + tlH;
		// Existing chart camera events are shown as reference blocks behind editable keys.
		// Add Camera Zoom stays visible only as the yellow event tick on the top ruler;
		// do not draw its impulse (track "kick") as a block on the Zoom Camera lane.
		for (e in chartCameraEvents)
		{
			var sourceLink = chartCameraLinkFor(e);
			if (sourceLink != null && !chartCameraLinkVisible(sourceLink)) continue;
			if (e.track == 'kick') continue;
			var x = xAt(e.time);
			var songEndX = xAt(songLen);
			var remainingWidth = Math.max(0, songEndX - x);
			var w = e.duration > 0 ? Math.min(e.duration * pps / 1000, remainingWidth) : Math.min(3, remainingWidth);
			if (x + w < TL_X || x > songEndX || x > FlxG.width) continue;
			var y = trackY(e.track, layerOf(e));
			var color:FlxColor = e.track == 'kick' ? 0xFFFFC76B : (e.track == 'focus' ? 0xFF42636B : (e.track == 'tilt' ? 0xFF3F6B4D : 0xFF574977));
			var drawX = Math.max(TL_X, x);
			var drawW = Math.max(1, Math.min(Math.min(FlxG.width, songEndX), x + w) - drawX);
			var refPad:Int = Std.int(Math.max(3, Math.round(rh * 13 / 54)));
			rect(drawX, y + refPad, drawW, rh - 2 * refPad, color);
			if (e == selected) frameRect(drawX, y + refPad - 1, drawW, rh - 2 * refPad + 2, 0xFFFFD16C, 2);
		}
		clipOn = false;
		for (event in previewChartEvents)
			if (event != null && event.name != null)
			{
				var lowerName = event.name.trim().toLowerCase();
				var hasCameraTrackBlock = ['focuscamera', 'focus camera', 'zoomcamera', 'zoom camera', 'target camera',
					'camera follow pos', 'camera warp pos', 'camera control', 'set camzoom', 'set camera zoom', 'defaultcamzoom', 'rol cam', 'roll camera'].contains(lowerName);
				if (!hasCameraTrackBlock && lowerName != 'add camera zoom')
				{
					var x = xAt(event.time);
					if (x >= TL_X && x < FlxG.width) rect(x, timelineTopY + 2, 2, 3, 0xFFFFC76B);
				}
			}
		// Draw one yellow ruler tick per Add Camera Zoom time, whether it came from the chart
		// or only from the saved camera-key file. This avoids a doubled/thicker marker on reload.
		var yellowKickTimes:Array<Float> = [];
		for (event in previewChartEvents)
			if (event != null && event.name != null && event.name.trim().toLowerCase() == 'add camera zoom')
			{
				var duplicateTick = false;
				for (oldTime in yellowKickTimes) if (sameCameraEventTime(oldTime, event.time)) { duplicateTick = true; break; }
				if (duplicateTick) continue;
				yellowKickTimes.push(event.time);
				var x = xAt(event.time);
				if (x >= TL_X && x < FlxG.width) rect(x, timelineTopY + 2, 3, 5, 0xFFFFC76B);
			}
		for (key in events)
			if (key != null && key.track == 'kick')
			{
				var duplicateTick = false;
				for (oldTime in yellowKickTimes) if (sameCameraEventTime(oldTime, key.time)) { duplicateTick = true; break; }
				if (duplicateTick) continue;
				yellowKickTimes.push(key.time);
				var x = xAt(key.time);
				if (x >= TL_X && x < FlxG.width) rect(x, timelineTopY + 2, 3, 5, 0xFFFFC76B);
			}

		clipOn = true;
		// blocks
		for (e in events)
		{
			// Add Camera Zoom is represented by its yellow top-ruler event tick, not by a block
			// in the Zoom Camera lane. It remains selectable/editable from the event list/properties.
			if (e.track == 'kick') continue;
			var x = xAt(e.time);
			var songEndX = xAt(songLen);
			var remainingWidth = Math.max(0, songEndX - x);
			var w = Math.min(Math.max(16, e.duration * pps / 1000), remainingWidth);
			if (x + w < TL_X || x > songEndX || x > FlxG.width)
				continue;
			if (e.track == 'general') continue;
			var y = trackY(e.track, layerOf(e));
			var base:FlxColor = e.track == "focus" ? 0xFF387B88 : (e.track == "tilt" ? 0xFF3E8F5A : 0xFF6651A2);
			var cx = Math.max(x, TL_X);
			var cw = Math.min(w - (cx - x), songEndX - cx);
			if (cw <= 0) continue;
			rect(cx, y + pad, cw, rh - 2 * pad, base);
			var inMulti = multiSel.indexOf(e) >= 0;
			frameRect(cx, y + pad, cw, rh - 2 * pad, e == selected ? 0xFFFFD16C : (inMulti ? 0xFFFFA64D : 0xFF9CA6B2), (e == selected || inMulti) ? 2 : 1);
			// ที่จับปรับความยาว: แถบกว้างที่ขอบขวา สว่างขึ้นเมื่อเมาส์อยู่ในโซนจับ
			var gripW:Float = Math.min(EDGE, cw * 0.5);
			var gripHover = mode == Resize ? e == dragEv : inRect(FlxG.mouse.gameX, FlxG.mouse.gameY, cx + cw - gripW, y, gripW + 5, rh);
			rect(cx + cw - gripW, y + pad, gripW, rh - 2 * pad, gripHover ? 0x99FFFFFF : 0x40FFFFFF);
			rect(cx + cw - 4, y + 2 * pad + 2, 2, rh - 4 * pad - 4, 0xFFFFFFFF);
		}

		// แถว GeneralCamera: ช่องสั้น ๆ บอกว่ากล้องหันไปหาใคร
		// จางๆ = การหันอัตโนมัติของเกมตาม Section (คลิกเพื่อควบคุมเอง) / ทึบ = key ที่ผู้ใช้วางเอง แก้และลบได้
		var genY = trackY("general");
		var secLabelIx = 0;
		var genVisible = genY + rh > timelineTopY + RULER_H && genY < timelineTopY + tlH;
		if (genVisible)
		{
			for (si in 0...sectionCameraTargets.length)
			{
				var ax = xAt(sectionCameraTargets[si].time);
				if (ax + GEN_W < TL_X || ax > FlxG.width) continue;
				if (!isAutoChange(si) || sectionHasGeneral(si)) continue;
				var acx = Math.max(TL_X, ax);
				var aw = GEN_W - (acx - ax);
				rect(acx, genY + pad, aw, rh - 2 * pad, whoColor(sectionWho[si]) & 0x66FFFFFF | 0x66000000);
				frameRect(acx, genY + pad, aw, rh - 2 * pad, 0x66FFFFFF, 1);
				if (secLabelIx < sectionLabels.length)
				{
					var sl = sectionLabels[secLabelIx++];
					setTextIfChanged(sl, whoShort(sectionWho[si]));
					sl.alpha = 0.6;
					sl.setPosition(acx + 4, genY + Math.max(0, (rh - sl.height) * 0.5));
					sl.visible = true;
				}
			}
			for (e in events)
			{
				if (e.track != 'general') continue;
				var gx = xAt(e.time);
				if (gx + GEN_W < TL_X || gx > FlxG.width) continue;
				var gcx = Math.max(TL_X, gx);
				var gw = GEN_W - (gcx - gx);
				var gInMulti = multiSel.indexOf(e) >= 0;
				rect(gcx, genY + pad, gw, rh - 2 * pad, whoColor(e.target));
				frameRect(gcx, genY + pad, gw, rh - 2 * pad, e == selected ? 0xFFFFD16C : (gInMulti ? 0xFFFFA64D : 0xFFE3E8EF), (e == selected || gInMulti) ? 2 : 1);
				if (secLabelIx < sectionLabels.length)
				{
					var gl = sectionLabels[secLabelIx++];
					setTextIfChanged(gl, whoShort(e.target));
					gl.alpha = 1;
					gl.setPosition(gcx + 4, genY + Math.max(0, (rh - gl.height) * 0.5));
					gl.visible = true;
				}
			}
		}
		for (k in secLabelIx...sectionLabels.length) sectionLabels[k].visible = false;
		clipOn = false;
		// Darken the unused tail so the ruler and keys visibly stop at the true song end.
		var endX = xAt(songLen);
		if (endX >= TL_X && endX < FlxG.width)
		{
			rect(endX + 1, timelineTopY, FlxG.width - endX, tlH, 0xB51A1D22);
			rect(endX, timelineTopY, 2, tlH, 0xFFFF766D);
		}

		// playhead
		var phx = xAt(songPos);
		if (phx >= TL_X && phx <= FlxG.width)
		{
			rect(phx - 3, timelineTopY - 1, 7, 5, 0xFF5AA9FF);
			rect(phx, timelineTopY + 3, 2, tlH - 3, 0xFF5AA9FF);
		}

		if (maxLayerScroll() > 0)
		{
			var vt = vScrollTrack();
			rect(vt.x, vt.y, vt.w, vt.h, 0xFF1B1F25);
			var thumbHover = mode == VScroll || inRect(FlxG.mouse.gameX, FlxG.mouse.gameY, vt.x - 2, vt.y, vt.w + 4, vt.h);
			rect(vt.x + 1, vScrollThumbY(), vt.w - 2, vScrollThumbH(), thumbHover ? 0xFF9AA6B5 : 0xFF6A7482);
		}

		if (mode == Marquee)
		{
			var gx = FlxG.mouse.gameX, gy = FlxG.mouse.gameY;
			var mLeft = Math.max(TL_X, Math.min(gx, marqueeX0));
			var mRight = Math.min(FlxG.width, Math.max(gx, marqueeX0));
			var mTop = Math.max(timelineTopY + RULER_H, Math.min(gy, marqueeY0));
			var mBottom = Math.min(timelineTopY + tlH, Math.max(gy, marqueeY0));
			if (mRight > mLeft && mBottom > mTop)
			{
				rect(mLeft, mTop, mRight - mLeft, mBottom - mTop, 0x305AA9FF);
				frameRect(mLeft, mTop, mRight - mLeft, mBottom - mTop, 0xFF5AA9FF, 1);
			}
		}

		drawOpenMenu(); // drawn last among the canvas layers: viewport border / passepartout / camera frame must not paint over the dropdown

		if (eventPickerOpen)
		{
			var pickerX = PREV_X + (PREV_W - 700) * 0.5;
			var pickerY = Math.max(8, Math.min(FlxG.height - 368, PREV_Y + (previewPanelHeight() - 360) * 0.5));
			rect(pickerX, pickerY, 700, 360, 0xF0232831);
			frameRect(pickerX, pickerY, 700, 360, 0xFF596676, 2);
			rect(pickerX + 1, pickerY + 38, 698, 1, 0xFF424B57);
			rect(pickerX + 350, pickerY + 48, 1, 270, 0xFF424B57);
			setTextIfChanged(eventPickerTitle, 'PLACE CHART EVENT  •  ${availableChartEvents.length} loaded');
			eventPickerTitle.setPosition(pickerX + 18, pickerY + 12);
			eventPickerTitle.visible = true;
			for (i in 0...eventPickerRows.length)
			{
				var eventIndex = eventPickerScroll + i;
				var row = eventPickerRows[i];
				if (eventIndex >= availableChartEvents.length)
				{
					row.visible = false;
					continue;
				}
				var rowY = pickerY + 48 + i * 30;
				if (eventIndex == eventPickerIndex) rect(pickerX + 12, rowY, 326, 27, 0xFF35515C);
				setTextIfChanged(row, availableChartEvents[eventIndex].name);
				row.setPosition(pickerX + 20, rowY + 5);
				row.visible = true;
			}
			var picked = eventPickerIndex >= 0 && eventPickerIndex < availableChartEvents.length ? availableChartEvents[eventPickerIndex] : null;
			setTextIfChanged(eventPickerDescription, picked == null ? '' : (picked.description == null || picked.description.length == 0 ? 'No description is available for this event.' : picked.description));
			eventPickerDescription.setPosition(pickerX + 370, pickerY + 52);
			eventPickerDescription.visible = true;
			setTextIfChanged(eventPickerFooter, '↑ ↓ choose    Enter / click to place at playhead    Esc cancel    Wheel scrolls the list');
			eventPickerFooter.setPosition(pickerX + 18, pickerY + 330);
			eventPickerFooter.visible = true;
		}
		else
		{
			eventPickerTitle.visible = false;
			eventPickerDescription.visible = false;
			eventPickerFooter.visible = false;
			for (row in eventPickerRows) row.visible = false;
		}

		// Bottom controls: auto-follow selector stays separated from the live curStep readout.
		var followRect = timelineFollowButtonRect();
		rect(followRect.x, followRect.y, followRect.w, followRect.h, 0xFF303640);
		frameRect(followRect.x, followRect.y, followRect.w, followRect.h, 0xFF4A5868, 1);
		if (timelineFollowText != null)
		{
			setTextIfChanged(timelineFollowText, 'Timeline Follow: ' + TIMELINE_FOLLOW_LABELS[timelineFollowMode]);
			timelineFollowText.setPosition(followRect.x + 8, followRect.y + 5);
			timelineFollowText.visible = true;
		}

		// Top resize handle: a thin separator plus one clearly visible centered grip.
		// The hit zone is larger than the artwork, so grabbing feels easy without blocking keys.
		var topGripY = timelineTopY - 3;
		var gripCenter = timelineGripCenter();
		rect(TL_X, timelineTopY - 1, FlxG.width - TL_X, 1, 0xFF29313B);
		rect(gripCenter - 52, topGripY - 2, 104, 7, 0xFF303842);
		frameRect(gripCenter - 52, topGripY - 2, 104, 7, 0xFF667B90, 1);
		for (tg in 0...7) rect(gripCenter - 18 + tg * 6, topGripY, 3, 2, 0xFFADB9C6);

		// Bottom handle lives in the gap beneath the track, so clicks on the last event row are safe.
		var trackBottom = timelineTopY + tlHeight();
		rect(TL_X, trackBottom, FlxG.width - TL_X, 1, 0xFF29313B);
		rect(gripCenter - 48, trackBottom + 3, 96, 5, 0xFF303842);
		frameRect(gripCenter - 48, trackBottom + 3, 96, 5, 0xFF667B90, 1);
		for (g in 0...7) rect(gripCenter - 18 + g * 6, trackBottom + 4, 3, 2, 0xFFADB9C6);

		// The editor playhead is also the current song position while playing, so this
		// stays accurate during playback, pause, and manual timeline scrubbing.
		if (curStepText != null)
		{
			var displayedStep = Std.int(Math.floor(Conductor.getStepRounded(songPos)));
			setTextIfChanged(curStepText, 'curStep: $displayedStep');
			curStepText.setPosition(FlxG.width - curStepText.width - 16, 687);
			curStepText.visible = true;
		}

		if (helpOpen)
		{
			// Modal layer: dim + panel + texts are real sprites re-added on top, so the FlxText labels
			// (timeline rows, panel list, VCAM info...) are dimmed too instead of glowing over the overlay.
			if (!helpLayered)
			{
				helpLayered = true;
				for (o in [helpDim, helpPanel, helpTitle, helpText, helpFooter])
				{
					remove(o, true);
					add(o);
				}
			}
			layoutHelp();
			setTextIfChanged(helpTitle, 'CAMERA EDITOR CONTROLS');
			setTextIfChanged(helpFooter, 'Press F1 or Esc to close this window');
			helpDim.visible = helpPanel.visible = true;
			helpTitle.visible = helpText.visible = helpFooter.visible = true;
		}
		else
		{
			helpLayered = false;
			helpDim.visible = helpPanel.visible = false;
			helpTitle.visible = false;
			helpText.visible = false;
			helpFooter.visible = false;
		}

		drawKeyWindow();
		canvas.dirty = true;
	}

	function fmtTime(ms:Float):String
	{
		var total = Std.int(ms / 1000);
		var m = Std.int(total / 60), sc = total % 60;
		return m + ":" + (sc < 10 ? "0" : "") + sc;
	}

	override function destroy()
	{
		restoreEditorMuteShortcut();
		restoreSuppressedPreviewCameraFX();
		stopPreviewEventVideo();
		// ออกจากหน้านี้ทางไหนก็ตาม (สลับเพลง/โหลด Chart ใหม่/ปิดเกม) ต้องมี backup ล่าสุดเสมอ
		if (!exitBackupDone && !createFailed) autosaveBackup(false);
		if (editorOriginalCursor != null)
			FlxG.mouse.load(editorOriginalCursor, 1, 1, 1);
		else
		{
			if (editorCursorDefault == null) editorCursorDefault = loadEditorCursorBitmap('cursor');
			if (editorCursorDefault != null) FlxG.mouse.load(editorCursorDefault, 1, 1, 1); else FlxG.mouse.unload();
		}
		FlxG.mouse.visible = false;
		previewEndPending = false;
		restoreRealCameraView();
		if (editorViewHooked)
		{
			FlxG.signals.preUpdate.remove(restoreRealCameraView);
			editorViewHooked = false;
		}
		#if LUA_ALLOWED
		if (stashedSongLuas.length > 0 && luaArray != null)
		{
			for (script in stashedSongLuas) luaArray.push(script); // ให้ PlayState.destroy ปิดสคริปต์ที่พักไว้ด้วย
			stashedSongLuas = [];
		}
		#end
		pauseCameraEditorPlayback();
		if (FlxG.cameras != null && FlxG.cameras.list != null)
			for (camera in FlxG.cameras.list)
				if (camera != null && originalCameraVisibility.exists(camera) && camera.flashSprite != null)
					camera.visible = originalCameraVisibility.get(camera) == true;
		if (previewInitTimer != null)
		{
			previewInitTimer.cancel();
			previewInitTimer.destroy();
			previewInitTimer = null;
		}
		if (jsonPicker != null) { jsonPicker.destroy(); jsonPicker = null; }
		if (chartPicker != null) { chartPicker.destroy(); chartPicker = null; }
		if (chartSavePicker != null) { chartSavePicker.destroy(); chartSavePicker = null; }
		// previewCamera is the actual PlayState camera; restore its viewport before
		// leaving so the next screen starts with the normal full-screen camera.
		if (previewCamera != null && previewCamera == camGame && previewCamera.flashSprite != null)
		{
			try
			{
				previewCamera.setPosition(originalGameCameraX, originalGameCameraY);
				if (originalGameCameraWidth > 0 && originalGameCameraHeight > 0)
					previewCamera.setSize(originalGameCameraWidth, originalGameCameraHeight);
			}
			catch (_:Dynamic) {}
		}
		previewCamera = null;
		// editorUICamera aliases luaTpadCam, which is owned and destroyed by PlayState.
		editorUICamera = null;
		// PlayState.destroy owns the actual scene, scripts, and audio cleanup.
		super.destroy();
		if (restoreMenuMusicAfterDestroy)
		{
			restoreMenuMusicAfterDestroy = false;
			restoreEditorMenuMusic();
		}
		// Clean up only mod-created transient sounds left behind by onDestroy callbacks.
		stopEditorTransientSounds();
		stageHost = null;
		previewNotes = [];
		previewChartEvents = [];
		previewBopEvents = [];
		previewZoomDecayEvents = [];
		chartCameraLinks = [];
		chartCameraEvents = [];
		sortedCameraEvents = [];
		focusCameraEvents = [];
		focusReleaseEvents = [];
		zoomCameraEvents = [];
		tiltCameraEvents = [];
		zoomKickEvents = [];
		sectionCameraTargets = [];
		stageTreeCameraSizes = [];
		previewScriptPaths = [];
		soundsBeforeEditor = [];
		availableChartEvents = [];
		cameraEventList = [];
		cameraEventRows = [];
		cameraEventVisibleEntries = [];
		dynamicPreviewMembers = [];
		dynamicPreviewGroupChildren = [];
		previewGroupMemberBaselines = new ObjectMap();
		previewStageUpdateArgs = [];
		easeCache = new Map();
	}
}
