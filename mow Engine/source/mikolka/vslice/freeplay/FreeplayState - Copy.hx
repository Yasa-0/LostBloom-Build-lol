package mikolka.vslice.freeplay;

import mikolka.vslice.freeplay.capsule.SongMenuItem;
import mikolka.vslice.freeplay.capsule.SongCapsuleGroup;
import mikolka.funkin.custom.mobile.MobileScaleMode;
import flixel.math.FlxRect;
import flixel.math.FlxMath;
import mikolka.vslice.ui.MainMenuState;
import mikolka.vslice.freeplay.backcards.LuaCard;
import mikolka.vslice.freeplay.obj.CapsuleOptionsMenu;
import mikolka.compatibility.funkin.FunkinControls;
import mikolka.vslice.charSelect.CharSelectSubState;
import openfl.filters.ShaderFilter;
import mikolka.vslice.freeplay.backcards.PicoCard;
import mikolka.funkin.freeplay.FreeplayStyleRegistry;
import mikolka.vslice.freeplay.backcards.BoyfriendCard;
import shaders.BlueFade;
import mikolka.funkin.freeplay.FreeplayStyle;
import mikolka.vslice.freeplay.backcards.BackingCard;
import mikolka.compatibility.ModsHelper;
import mikolka.compatibility.VsliceOptions;
import mikolka.compatibility.funkin.FunkinCamera;
import mikolka.vslice.freeplay.pslice.BPMCache;
import mikolka.compatibility.freeplay.FreeplaySongData;
import mikolka.compatibility.freeplay.FreeplayHelpers;
import mikolka.compatibility.funkin.FunkinPath as Paths;
import mikolka.funkin.custom.VsliceSubState as MusicBeatSubstate;
import openfl.utils.AssetCache;
import mikolka.funkin.AtlasText;
import shaders.PureColor;
import shaders.HSVShader;
import shaders.StrokeShader;
import shaders.AngleMask;
import mikolka.funkin.IntervalShake;
import mikolka.vslice.StickerSubState;
import mikolka.funkin.Scoring.ScoringRank;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.math.FlxPoint;
import openfl.display.BlendMode;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import haxe.Json;

/**
 * Parameters used to initialize the FreeplayState.
 */
typedef FreeplayStateParams =
{
	?fromCharSelect:Bool,
	?fromResults:FromResultsParams,
};

/**
 * A set of parameters for transitioning to the FreeplayState from the ResultsState.
 */
typedef FromResultsParams =
{
	var ?oldRank:ScoringRank;
	var playRankAnim:Bool;
	var newRank:ScoringRank;
	var songId:String;
	var difficultyId:String;
};

/**
 * The state for the freeplay menu, allowing the player to select any song to play.
 */
class FreeplayState extends MusicBeatSubstate
{
	final currentCharacterId:String;
	final currentCharacter:PlayableCharacter;

	public static final FADE_IN_DURATION:Float = 2;
	public static final FADE_OUT_DURATION:Float = 0.25;
	public static final FADE_IN_START_VOLUME:Float = 0;
	public static final FADE_IN_END_VOLUME:Float = 0.7;
	public static final FADE_IN_DELAY:Float = 0.25;
	public static final FADE_OUT_END_VOLUME:Float = 0.0;

	public static var CUTOUT_WIDTH:Float = MobileScaleMode.gameCutoutSize.x / 1.5;
	public static final DJ_POS_MULTI:Float = 0.44;
	public static final SONGS_POS_MULTI:Float = 0.75;

	var songs:Array<Null<FreeplaySongData>> = [];
	var diffIdsCurrent:Array<String> = [];
	var diffIdsTotal:Array<String> = []; 

	var curSelected:Int = 0;
	var curSelectedFractal:Float = 0;
	var currentDifficulty:String = Constants.DEFAULT_DIFFICULTY;

	var fp:FreeplayScore;
	var txtCompletion:AtlasText;
	var lerpCompletion:Float = 0;
	var intendedCompletion:Float = 0;
	var lerpScore:Float = 0;
	var intendedScore:Int = 0;

	var grpDifficulties:FlxTypedSpriteGroup<DifficultySprite>;
	var grpSongs:FlxTypedGroup<Alphabet>;
	var grpCapsules:SongCapsuleGroup;
	var curCapsule(get,never):SongMenuItem;
	function get_curCapsule() {
		return grpCapsules.activeSongItems[curSelected];
	}
	var curPlaying:Bool = false;

	var ostName:FlxText;
	var albumRoll:AlbumRoll;
	var charSelectHint:FlxText;
	var letterSort:LetterSort;
	var exitMovers:ExitMoverData = new Map();
	var exitMoversCharSel:ExitMoverData = new Map();
	var diffSelLeft:DifficultySelector;
	var diffSelRight:DifficultySelector;
	var stickerSubState:Null<StickerSubState> = null;

	public static var rememberedDifficulty:String = Constants.DEFAULT_DIFFICULTY;
	public static var rememberedSongId:Null<String> = 'tutorial';
	public static var instance:FreeplayState;

	var funnyCam:FunkinCamera;
	var rankCamera:FunkinCamera;
	var camUI:FunkinCamera; // กล้องใหม่สำหรับ UI ที่ล็อกตำแหน่ง
	var rankBg:FunkinSprite;
	var rankVignette:FlxSprite;

	var backingCard:Null<BackingCard> = null;
	public var backingImage:FlxSprite;
	var fromResultsParams:Null<FromResultsParams> = null;
	var prepForNewRank:Bool = false;
	var styleData:Null<FreeplayStyle> = null;
	var fromCharSelect:Null<Bool> = null;

	// Custom Variable for Left Character
	var leftCharSprite:FlxSprite;

	// ============================================
	// ตัวแปรสำหรับระบบ Preview Events หน้าจอจาก Chart
	// ============================================
	var previewEvents:Array<{time:Float, name:String, v1:String, v2:String}> = [];
	var currentEventIndex:Int = 0;

	public function new(?params:FreeplayStateParams, ?stickers:StickerSubState)
	{
		instance = this;
		controls.isInSubstate = true;
		super();
		var saveBox = VsliceOptions.LAST_MOD;
		currentCharacterId = saveBox.char_name;

		if (ModsHelper.isModDirEnabled(saveBox.mod_dir))
			ModsHelper.loadModDir(saveBox.mod_dir);

		CUTOUT_WIDTH = MobileScaleMode.gameCutoutSize.x / 1.5;

		var result = PlayerRegistry.instance.fetchEntry(currentCharacterId);
		if (result == null)
		{
			currentCharacterId = Constants.DEFAULT_CHARACTER;
			result = PlayerRegistry.instance.fetchEntry(Constants.DEFAULT_CHARACTER);
		}
		currentCharacter = result;

		styleData = FreeplayStyleRegistry.instance.fetchEntry(currentCharacter.getFreeplayStyleID());
		if (styleData == null)
			styleData = FreeplayStyleRegistry.instance.fetchEntry("bf");

		fromCharSelect = params?.fromCharSelect;
		fromResultsParams = params?.fromResults;

		if (fromResultsParams?.playRankAnim == true)
		{
			prepForNewRank = true;
		}

		if (stickers?.members != null)
		{
			stickerSubState = stickers;
		}
	}

	var fadeShader:BlueFade = new BlueFade();
	public var angleMaskShader:AngleMask = new AngleMask();

	override function create():Void
	{
		SongMenuItem.reloadGlobalItemData();
		var saveBox = VsliceOptions.LAST_MOD;
		if (ModsHelper.isModDirEnabled(saveBox.mod_dir))
			ModsHelper.loadModDir(saveBox.mod_dir);

		if (VsliceOptions.FP_CARDS)
		{
			switch (currentCharacterId)
			{
				case(VsliceOptions.LOW_QUALITY) => true:
					backingCard = null;
				#if (!LEGACY_PSYCH && HSCRIPT_ALLOWED)
				case(LuaCard.hasCustomCard(currentCharacterId)) => true:
					backingCard = new LuaCard(currentCharacter, currentCharacterId, stickerSubState == null);
				#end
				case 'bf':
					backingCard = new BoyfriendCard(currentCharacter);
				case 'pico':
					backingCard = new PicoCard(currentCharacter);
				default:
					backingCard = new BoyfriendCard(currentCharacter);
			}
		}
		else
			backingCard = new BoyfriendCard(currentCharacter);

		albumRoll = new AlbumRoll();
		fp = new FreeplayScore(FlxG.width - (MobileScaleMode.gameNotchSize.x + 353), 60, 7, 100, styleData);
		rankCamera = new FunkinCamera('rankCamera', 0, 0, FlxG.width, FlxG.height);
		funnyCam = new FunkinCamera('freeplayFunny', 0, 0, FlxG.width, FlxG.height);
		camUI = new FunkinCamera('camUI', 0, 0, FlxG.width, FlxG.height);
		
		grpCapsules = new SongCapsuleGroup(styleData);
		grpCapsules.onRandomSelected.add(capsuleOnConfirmRandom);
		grpCapsules.onSongSelected.add(capsuleOnOpenDefault);
		
		letterSort = new LetterSort((CUTOUT_WIDTH * SONGS_POS_MULTI) + 400, 75);
		grpSongs = new FlxTypedGroup<Alphabet>();
		rankBg = new FunkinSprite(0, 0);
		rankVignette = new FlxSprite(0, 0).loadGraphic(Paths.image('freeplay/rankVignette'));
		sparks = new FlxSprite(0, 0);
		sparksADD = new FlxSprite(0, 0);
		txtCompletion = new AtlasText(FlxG.width - (MobileScaleMode.gameNotchSize.x+95), 87, '69', AtlasFont.FREEPLAY_CLEAR);

		// ดึงชื่อ Mod มาแสดงในข้อความ OST
		var modTitle = "OFFICIAL OST";
		if (saveBox != null && saveBox.mod_dir != null && saveBox.mod_dir != "" && saveBox.mod_dir != "null")
		{
			modTitle = saveBox.mod_dir.toUpperCase() + " OST";
		}
		ostName = new FlxText(8-MobileScaleMode.gameNotchSize.x, 8, FlxG.width - 8 - 8, modTitle, 48);
		
		charSelectHint = new FlxText(-40, 18, FlxG.width - 8 - 8, 'Press [ LOL ] to change characters', 32);
		
		charSelectHint.visible = false;

		backingImage = new FlxSprite((backingCard?.pinkBack.width ?? 0) * 0.74,
			0).loadGraphic(styleData == null ? 'freeplay/freeplayBGdad' : styleData.getBgAssetGraphic());

		BPMCache.instance.clearCache();

		super.create();
		var diffIdsTotalModBinds:Map<String, String> = new Map();

		FlxG.state.persistentUpdate = false;
		FlxTransitionableState.skipNextTransIn = true;

		var fadeShaderFilter:ShaderFilter = new ShaderFilter(fadeShader);
		ModsHelper.setFiltersOnCam(funnyCam, [fadeShaderFilter]);
		funnyCam.filtersEnabled = false;

		if (stickerSubState != null)
		{
			this.persistentUpdate = true;
			this.persistentDraw = true;

			openSubState(stickerSubState);
			stickerSubState.degenStickers();
		}

		busy = true;

		songs.push(null);
		PlayState.isStoryMode = false;
		for (sngCard in FreeplayHelpers.loadSongs())
		{
			if (currentCharacter.shouldShowUnownedChars())
			{
				if (sngCard.songPlayer != '' && sngCard.songPlayer != currentCharacterId)
					continue;
			}
			else
			{
				if (sngCard.songPlayer == '' || sngCard.songPlayer != currentCharacterId)
					continue;
			}
			songs.push(sngCard);

			for (difficulty in sngCard.songDifficulties)
			{
				diffIdsTotal.pushUnique(difficulty);
				if (!diffIdsTotalModBinds.exists(difficulty))
					diffIdsTotalModBinds.set(difficulty, sngCard.folder);
			}
		}

		if (diffIdsTotal.length > 0)
		{
			var matchDiff:String = null;
			for (d in diffIdsTotal)
			{
				if (d != null && d.toLowerCase() == currentDifficulty.toLowerCase())
				{
					matchDiff = d;
					break;
				}
			}
			currentDifficulty = (matchDiff != null) ? matchDiff : diffIdsTotal[0];
			rememberedDifficulty = currentDifficulty;
		}

		if (backingCard != null)
		{
			add(backingCard);
			backingCard.init();
			backingCard.applyExitMovers(exitMovers, exitMoversCharSel);
			backingCard.instance = this;
		}

		if (!VsliceOptions.LOW_QUALITY)
			backingImage.shader = angleMaskShader;
		backingImage.visible = false;

		var blackOverlayBullshitLOLXD:FlxSprite = new FlxSprite(FlxG.width).makeGraphic(Std.int(backingImage.width), Std.int(backingImage.height), FlxColor.BLACK);
    	add(blackOverlayBullshitLOLXD);
		blackOverlayBullshitLOLXD.shader = backingImage.shader;
		
		if (VsliceOptions.LOW_QUALITY)
			backingImage.setGraphicSize(FlxG.width, FlxG.height);
		else
			backingImage.setGraphicSize(0, FlxG.height);
		blackOverlayBullshitLOLXD.setGraphicSize(0, FlxG.height);

		backingImage.updateHitbox();
		blackOverlayBullshitLOLXD.updateHitbox();

		exitMovers.set([blackOverlayBullshitLOLXD, backingImage], {
			x: FlxG.width * 1.5,
			speed: 0.4,
			wait: 0
		});

		exitMoversCharSel.set([blackOverlayBullshitLOLXD, backingImage], {
			y: -100,
			speed: 0.8,
			wait: 0.1
		});

		if(VsliceOptions.LOW_QUALITY) add(backingImage);

		// Setup Custom Left Character Sprite
		leftCharSprite = new FlxSprite(20, 0);
		leftCharSprite.antialiasing = true;
		leftCharSprite.visible = false;
		add(leftCharSprite);
		
		exitMovers.set([leftCharSprite], {
			x: -500,
			speed: 0.3
		});
		exitMoversCharSel.set([leftCharSprite], {
			y: -270,
			speed: 0.8,
			wait: 0.1
		});

		grpDifficulties = new FlxTypedSpriteGroup<DifficultySprite>(-300, 80);
		add(grpDifficulties);

		if(!VsliceOptions.LOW_QUALITY) add(backingImage);

		blackOverlayBullshitLOLXD.shader = backingImage.shader;

		rankBg.makeSolidColor(FlxG.width, FlxG.height, 0xD3000000);
		add(rankBg);
		add(grpSongs);
		add(grpCapsules);

		exitMovers.set([grpDifficulties], {
			x: -300,
			speed: 0.25,
			wait: 0
		});

		exitMoversCharSel.set([grpDifficulties], {
			y: -270,
			speed: 0.8,
			wait: 0.1
		});

		for (diffId in diffIdsTotal)
		{
			ModsHelper.loadModDir(diffIdsTotalModBinds.get(diffId));
			var diffSprite:DifficultySprite = new DifficultySprite(diffId);
			diffSprite.difficultyId = diffId;
			grpDifficulties.add(diffSprite);
		}
		ModsHelper.loadModDir(VsliceOptions.LAST_MOD.mod_dir); 

		grpDifficulties.group.forEach(function(spr)
		{
			spr.visible = false;
		});

		for (diffSprite in grpDifficulties.group.members)
		{
			if (diffSprite == null)
				continue;
			if (diffSprite.difficultyId.toLowerCase() == currentDifficulty.toLowerCase())
				diffSprite.visible = true;
		}

		albumRoll.albumId = null;
		@:privateAccess 
		albumRoll.updateAlbum();
		albumRoll.visible = false; // เอา text ที่วิ่งอยู่ด้านหลังออก
		add(albumRoll);

		var overhangStuff:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, 164, FlxColor.BLACK);
		overhangStuff.y -= overhangStuff.height;

		if (fromCharSelect == true)
		{
			blackOverlayBullshitLOLXD.visible = false;
			overhangStuff.y = -100;
			backingCard?.skipIntroTween();
		}
		else
		{
			albumRoll.applyExitMovers(exitMovers, exitMoversCharSel);
			FlxTween.tween(overhangStuff, {y: -100}, 0.3, {ease: FlxEase.quartOut});
			FlxTween.tween(blackOverlayBullshitLOLXD, {x: backingImage.x}, 0.7, {ease: FlxEase.quintOut});
		}

		var topLeftCornerText:FlxText = new FlxText(Math.max(MobileScaleMode.gameNotchSize.x, 8), 8, 0, 'FREEPLAY', 48);
		topLeftCornerText.font = 'VCR OSD Mono';
		topLeftCornerText.visible = false;

		var freeplayTxtBg:FlxSprite = new FlxSprite().makeGraphic(Math.round(topLeftCornerText.width + 16), Math.round(topLeftCornerText.height + 16),
		FlxColor.BLACK);
		freeplayTxtBg.x = topLeftCornerText.x - 8;
		freeplayTxtBg.visible = false;

		ostName.font = 'VCR OSD Mono';
		ostName.alignment = RIGHT;
		ostName.visible = false;

		charSelectHint.alignment = CENTER;
		charSelectHint.font = "5by7";
		charSelectHint.color = 0xFF5F5F5F;
		charSelectHint.text = controls.mobileC ? 'Touch [ X ] to change characters' : 'Press [ ${FunkinControls.FREEPLAY_CHAR_name()} ] to change characters';
		charSelectHint.y -= 100;

		exitMovers.set([overhangStuff,freeplayTxtBg, topLeftCornerText, ostName, charSelectHint], {
			y: -overhangStuff.height,
			x: 0,
			speed: 0.2,
			wait: 0
		});

		exitMoversCharSel.set([overhangStuff,freeplayTxtBg, topLeftCornerText, ostName, charSelectHint], {
			y: -300,
			speed: 0.8,
			wait: 0.1
		});

		var sillyStroke:StrokeShader = new StrokeShader(0xFFFFFFFF, 2, 2);
		topLeftCornerText.shader = sillyStroke;
		ostName.shader = sillyStroke;

		var fnfHighscoreSpr:FlxSprite = new FlxSprite(FlxG.width-MobileScaleMode.gameNotchSize.x-420, 70);
		fnfHighscoreSpr.frames = Paths.getSparrowAtlas('freeplay/highscore');
		fnfHighscoreSpr.animation.addByPrefix('highscore', 'highscore small instance 1', 24, false);
		fnfHighscoreSpr.visible = false;
		fnfHighscoreSpr.setGraphicSize(0, Std.int(fnfHighscoreSpr.height * 1));
		fnfHighscoreSpr.updateHitbox();
		add(fnfHighscoreSpr);

		new FlxTimer().start(FlxG.random.float(12, 50), function(tmr)
		{
			fnfHighscoreSpr?.animation?.play('highscore');
			tmr.time = FlxG.random.float(20, 60);
		}, 0);

		fp.visible = false;
		add(fp);

		var clearBoxSprite:FlxSprite = new FlxSprite(FlxG.width - MobileScaleMode.gameNotchSize.x -115, 65).loadGraphic(Paths.image('freeplay/clearBox'));
		clearBoxSprite.visible = false;
		add(clearBoxSprite);

		txtCompletion.visible = false;
		add(txtCompletion);

		add(letterSort);
		letterSort.visible = false;

		exitMovers.set([letterSort], {
			y: -100,
			speed: 0.3
		});

		exitMoversCharSel.set([letterSort], {
			y: -270,
			speed: 0.8,
			wait: 0.1
		});

		letterSort.changeSelectionCallback = (str) ->
		{
			switch (str)
			{
				case 'fav':
					generateSongList({filterType: FAVORITE}, true, false);
				case 'ALL':
					generateSongList(null, true, false);
				case '#':
					generateSongList({filterType: REGEXP, filterData: '0-9'}, true, false);
				default:
					generateSongList({filterType: REGEXP, filterData: str}, true, false);
			}

			if (grpCapsules.activeSongItems.length > 0)
			{
				FunkinSound.playOnce(Paths.sound('scrollMenu'), 0.4);
				curSelected = 1;
				curSelectedFractal = 1;
				changeSelection();
			}
		};

		exitMovers.set([fp, txtCompletion, fnfHighscoreSpr, clearBoxSprite], {
			x: FlxG.width,
			speed: 0.3
		});

		exitMoversCharSel.set([fp, txtCompletion, fnfHighscoreSpr, clearBoxSprite], {
			y: -270,
			speed: 0.8,
			wait: 0.1
		});

		diffSelLeft = new DifficultySelector(this, (CUTOUT_WIDTH * DJ_POS_MULTI) + 20, grpDifficulties.y - 10, false, controls, styleData);
		diffSelRight = new DifficultySelector(this, (CUTOUT_WIDTH * DJ_POS_MULTI) + 325, grpDifficulties.y - 10, true, controls, styleData);
		diffSelLeft.visible = false;
		diffSelRight.visible = false;
		add(diffSelLeft);
		add(diffSelRight);

		add(overhangStuff);
		add(freeplayTxtBg);
		add(topLeftCornerText);
		add(ostName);

		var onDJIntroDone = function()
		{
			busy = false;

			if (curCapsule != null) 
			{
				albumRoll.playIntro();
				var daSong = curCapsule.songData;
				albumRoll.albumId = daSong?.albumId;
			}
			else
				albumRoll.albumId = '';

			if (fromCharSelect == null)
			{
				if (_parentState != null)
					_parentState.persistentDraw = false;

				FlxTween.color(backingImage, 0.6, 0xFF000000, 0xFFFFFFFF, {
					ease: FlxEase.expoOut,
					onUpdate: function(_)
					{
						angleMaskShader.extraColor = backingImage.color;
					},
					onComplete: function(_) {
              			blackOverlayBullshitLOLXD.visible = false;
            		}
				});
			}

			FlxTween.cancelTweensOf(grpDifficulties);
			for (diff in grpDifficulties.group.members)
			{
				if (diff == null)
					continue;
				FlxTween.cancelTweensOf(diff);
				FlxTween.tween(diff, {x: (CUTOUT_WIDTH * DJ_POS_MULTI) + 90 }, 0.6, {ease: FlxEase.quartOut});
				diff.y = 80;
				diff.visible = diff.difficultyId.toLowerCase() == currentDifficulty.toLowerCase();
			}
			FlxTween.tween(grpDifficulties, {x: (CUTOUT_WIDTH * DJ_POS_MULTI) + 90}, 0.6, {ease: FlxEase.quartOut});

			diffSelLeft.visible = true;
			diffSelRight.visible = true;
			letterSort.visible = true;

			exitMovers.set([diffSelLeft, diffSelRight], {
				x: -diffSelLeft.width * 2,
				speed: 0.26
			});

			exitMoversCharSel.set([diffSelLeft, diffSelRight], {
				y: -270,
				speed: 0.8,
				wait: 0.1
			});

			new FlxTimer().start(1 / 24, function(handShit)
			{
				fnfHighscoreSpr.visible = true;
				freeplayTxtBg.visible = true;
				topLeftCornerText.visible = true;
				ostName.visible = true;
				fp.visible = true;
				fp.updateScore(0);

				clearBoxSprite.visible = true;
				txtCompletion.visible = true;
				intendedCompletion = 0;

				new FlxTimer().start(1.5 / 24, function(bold)
				{
					sillyStroke.width = 0;
					sillyStroke.height = 0;
					changeSelection();
				});
			});

			backingImage.visible = true;
			backingCard?.introDone();

			if (prepForNewRank && fromResultsParams != null)
			{
				rankAnimStart(fromResultsParams);
			}
		};

		FlxTimer.wait(0.2, () -> onDJIntroDone());

		if (rememberedDifficulty != null && diffIdsTotal.length > 0)
		{
			var match:String = null;
			for (d in diffIdsTotal)
			{
				if (d != null && d.toLowerCase() == rememberedDifficulty.toLowerCase())
				{
					match = d;
					break;
				}
			}
			currentDifficulty = (match != null) ? match : diffIdsTotal[0];
			rememberedDifficulty = currentDifficulty;
		}

		generateSongList(null, true, false);

		funnyCam.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(funnyCam, false);

		rankVignette.scale.set(2 * MobileScaleMode.wideScale.x, 2 * MobileScaleMode.wideScale.y);
		rankVignette.updateHitbox();
		rankVignette.blend = BlendMode.ADD;
		add(rankVignette);
		rankVignette.alpha = 0;

		forEach(function(bs)
		{
			bs.cameras = [funnyCam];
		});

		// กำหนดให้ UI อยู่บน camUI (ล็อกไว้ไม่ขยับเวลาซูม)
		camUI.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(camUI, false);

		fp.camera = camUI;
		txtCompletion.cameras = [camUI];
		clearBoxSprite.cameras = [camUI];
		fnfHighscoreSpr.cameras = [camUI];
		
		ostName.cameras = [camUI];
		topLeftCornerText.cameras = [camUI];
		freeplayTxtBg.cameras = [camUI];
		overhangStuff.cameras = [camUI];
		charSelectHint.cameras = [camUI];
		
		letterSort.cameras = [camUI];

		grpDifficulties.cameras = [camUI];
		if(diffSelLeft != null) diffSelLeft.cameras = [camUI];
		if(diffSelRight != null) diffSelRight.cameras = [camUI];

		rankCamera.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(rankCamera, false);
		rankBg.cameras = [rankCamera];
		rankBg.alpha = 0;

		if (prepForNewRank)
		{
			rankCamera.fade(0xFF000000, 0, false, null, true);
		}

		#if TOUCH_CONTROLS_ALLOWED
		addTouchPad('NONE', 'A_B_C_X_Y_F');
		addTouchPadCamera();
		if (prepForNewRank)
		{
			final lastAlpha:Float = touchPad.alpha;
			touchPad.alpha = 0;
			FlxTween.tween(touchPad, {alpha: lastAlpha}, 1.6, {ease: FlxEase.circOut});
		}
		else if (!fromCharSelect)
		{
			touchPad.forEachAlive(function(button:TouchButton)
			{
				if (button.tag == 'UP' || button.tag == 'DOWN')
				{
					button.x -= 350;
					FlxTween.tween(button, {x: button.x + 350}, 0.6, {ease: FlxEase.backInOut});
				}
				else
				{
					button.x += 450;
					FlxTween.tween(button, {x: button.x - 450}, 0.6, {ease: FlxEase.backInOut});
				}
			});
		}
		#if !LEGACY_PSYCH
		var button = new TouchZone( (CUTOUT_WIDTH * SONGS_POS_MULTI) +420, 260, 450, 95);
		button.cameras = [funnyCam];

		var scroll = new ScrollableObject(-0.02, (CUTOUT_WIDTH * SONGS_POS_MULTI)+150, 100, FlxG.width - 400, FlxG.height, button);
		scroll.cameras = [funnyCam];
		scroll.onPartialScroll.add(delta ->
		{
			if (busy)
				return;
			changeSelectionFractal(delta);
		});
		scroll.onFullScrollSnap.add(() -> changeSelectionFractal(curSelected - curSelectedFractal));
		scroll.onFullScroll.add(delta ->
		{
			if (busy)
				return;
			changeSelection(delta, false);
		});
		scroll.onTap.add(() ->
		{
			if (busy)
				return;
			var daSongCapsule:SongMenuItem = curCapsule;
			daSongCapsule.onConfirm();
		});
		add(scroll);
		add(button);
		#end
		#end

		if (fromCharSelect == true)
		{
			enterFromCharSel();
			onDJIntroDone();
		}
	}

	function updateLeftCharacter()
	{
		if (leftCharSprite == null) return;

		var songId:String = "missing";
		var diffId:String = currentDifficulty != null ? currentDifficulty.toLowerCase() : "";
		var charName:String = "bf";
		var offsetX:Float = 20;
		var offsetY:Float = 0;
		var customScale:Float = 1.0; 
		var hasCustomY:Bool = false;

		var isRandomOrMissing:Bool = (curCapsule == null || curCapsule.songData == null || curSelected == 0);

		if (!isRandomOrMissing) 
		{
			songId = curCapsule.songData.songId;
			
			try {
				var jsonString:String = null;
				var pathAssets = 'assets/data/' + songId + '/freeplay_char.json';
				var pathModsGlobal = 'mods/data/' + songId + '/freeplay_char.json';
				
				#if sys
				if (sys.FileSystem.exists(pathAssets)) jsonString = sys.io.File.getContent(pathAssets);
				else if (sys.FileSystem.exists(pathModsGlobal)) jsonString = sys.io.File.getContent(pathModsGlobal);
				else {
					var modFolder = curCapsule.songData.folder;
					if (modFolder != null && modFolder != "") {
						var pathModSpecific = 'mods/' + modFolder + '/data/' + songId + '/freeplay_char.json';
						if (sys.FileSystem.exists(pathModSpecific)) jsonString = sys.io.File.getContent(pathModSpecific);
					}
				}
				#else
				if (openfl.Assets.exists(pathAssets)) jsonString = openfl.Assets.getText(pathAssets);
				#end

				if (jsonString != null && jsonString.length > 0) {
					var songJsonData:Dynamic = Json.parse(jsonString);
					if (Reflect.hasField(songJsonData, "char")) charName = Std.string(Reflect.field(songJsonData, "char"));
					if (Reflect.hasField(songJsonData, "x")) offsetX = Std.parseFloat(Std.string(Reflect.field(songJsonData, "x")));
					if (Reflect.hasField(songJsonData, "y")) {
						offsetY = Std.parseFloat(Std.string(Reflect.field(songJsonData, "y")));
						hasCustomY = true;
					}
					if (Reflect.hasField(songJsonData, "scale")) customScale = Std.parseFloat(Std.string(Reflect.field(songJsonData, "scale")));
				}
			} catch (e:Dynamic) {}
		}

		var loadedGraphic = null;
		
		if (!isRandomOrMissing) 
		{
			var basePath:String = 'freeplay/WeekCur/' + songId + '/' + charName;
			var diffPath:String = basePath + '-' + diffId;

			loadedGraphic = Paths.image(diffPath);
			if (loadedGraphic == null) {
				loadedGraphic = Paths.image(basePath);
			}
		}

		if (loadedGraphic == null) 
		{
			charName = "yasa";
			offsetX = -50;
			offsetY = 180;
			customScale = 0.9;
			hasCustomY = true;
			
			loadedGraphic = Paths.image('freeplay/WeekCur/missing/' + charName);
			
			if (loadedGraphic == null) {
				loadedGraphic = Paths.image('freeplay/WeekCur/missing');
			}
		}

		if (loadedGraphic != null)
		{
			leftCharSprite.loadGraphic(loadedGraphic);
			leftCharSprite.visible = true;
			
			leftCharSprite.scale.set(customScale, customScale);
			leftCharSprite.updateHitbox();

			FlxTween.cancelTweensOf(leftCharSprite);

			if (hasCustomY) leftCharSprite.y = offsetY;
			else leftCharSprite.screenCenter(Y);

			var targetX = offsetX + Math.max(MobileScaleMode.gameNotchSize.x, 0); 
			
			leftCharSprite.x = -leftCharSprite.width - 200;
			FlxTween.tween(leftCharSprite, {x: targetX}, 0.4, {ease: flixel.tweens.FlxEase.expoOut});
		}
		else
		{
			leftCharSprite.visible = false;
		}
	}

	var currentFilter:SongFilter = null;
	var currentFilteredSongs:Array<FreeplaySongData> = [];

	public function generateSongList(filterStuff:Null<SongFilter>, force:Bool = false, onlyIfChanged:Bool = true):Void
	{
		if (rememberedDifficulty != null && diffIdsTotal.length > 0)
		{
			var foundDiff:String = null;
			for (d in diffIdsTotal)
			{
				if (d != null && d.toLowerCase() == rememberedDifficulty.toLowerCase())
				{
					foundDiff = d;
					break;
				}
			}
			if (foundDiff != null)
				currentDifficulty = foundDiff;
			else if (currentDifficulty == null || !diffIdsTotal.contains(currentDifficulty))
				currentDifficulty = diffIdsTotal[0];

			rememberedDifficulty = currentDifficulty;
		}

		var tempSongs:Array<Null<FreeplaySongData>> = songs;

		if (filterStuff != null)
			tempSongs = sortSongs(tempSongs, filterStuff);

		if (currentDifficulty != null)
		{
			tempSongs = tempSongs.filter(song ->
			{
				if (song == null)
					return true;
				for (d in song.songDifficulties)
				{
					if (d != null && d.toLowerCase() == currentDifficulty.toLowerCase())
						return true;
				}
				return false;
			});
		}

		if (tempSongs.length <= 1 && songs.length > 1 && diffIdsTotal.length > 0)
		{
			for (diff in diffIdsTotal)
			{
				var testSongs = songs.filter(s -> {
					if (s == null) return true;
					for (d in s.songDifficulties)
					{
						if (d != null && d.toLowerCase() == diff.toLowerCase())
							return true;
					}
					return false;
				});
				if (testSongs.length > 1)
				{
					currentDifficulty = diff;
					rememberedDifficulty = diff;
					tempSongs = testSongs;
					break;
				}
			}
		}

		if (onlyIfChanged && !force)
		{
			if (tempSongs.isEqualUnordered(currentFilteredSongs))
				return;
		}

		rememberedSongId = curCapsule?.songData?.songId ?? rememberedSongId;

		currentFilter = filterStuff;

		currentFilteredSongs = tempSongs;
		curSelected = 0;
		curSelectedFractal = 0;

		grpCapsules.generateFullSongList(tempSongs, currentDifficulty,
			difficultyLastChange > 0 ? SLIDE_RIGHT : SLIDE_LEFT, 
			fromCharSelect ? SLIDE_LEFT : JUMPIN_FORCE);

		rememberSelection();

		changeSelection();
		changeDiff(0);
		grpCapsules.setInitialAnimPosition();
	}

	public function sortSongs(songsToFilter:Array<Null<FreeplaySongData>>, songFilter:SongFilter):Array<Null<FreeplaySongData>>
	{
		var filterAlphabetically = function(a:Null<FreeplaySongData>, b:Null<FreeplaySongData>):Int
		{
			return SortUtil.alphabetically(a?.songName ?? '', b?.songName ?? '');
		};

		switch (songFilter.filterType)
		{
			case REGEXP:
				var filterRegexp:EReg = new EReg('^[' + songFilter.filterData + '].*', 'i');
				songsToFilter = songsToFilter.filter(str ->
				{
					if (str == null)
						return true;
					return filterRegexp.match(str.songName);
				});

				songsToFilter.sort(filterAlphabetically);

			case STARTSWITH:
				songsToFilter = songsToFilter.filter(str ->
				{
					if (str == null)
						return true;
					return str.songName.toLowerCase().startsWith(songFilter.filterData ?? '');
				});
			case ALL:
			case FAVORITE:
				songsToFilter = songsToFilter.filter(str ->
				{
					if (str == null)
						return true; 
					return str.isFav;
				});

				songsToFilter.sort(filterAlphabetically);

			default:
		}

		return songsToFilter;
	}

	var sparks:FlxSprite;
	var sparksADD:FlxSprite;

	function rankAnimStart(fromResults:FromResultsParams):Void
	{
		busy = true;
		curCapsule.sparkle.alpha = 0;

		rememberedSongId = fromResults.songId;
		rememberedDifficulty = fromResults.difficultyId;
		changeSelection();
		changeDiff();

		rankCamera.fade(0xFF000000, 0.5, true, null, true);
		if (FlxG.sound.music != null)
			FlxG.sound.music.volume = 0;
		rankBg.alpha = 0.6;

		if (fromResults.oldRank != null)
		{
			curCapsule.setFakeRanking(fromResults.oldRank);

			sparks.frames = Paths.getSparrowAtlas('freeplay/sparks');
			sparks.animation.addByPrefix('sparks', 'sparks', 24, false);
			sparks.visible = false;
			sparks.blend = BlendMode.ADD;
			sparks.setPosition(517, 134);
			sparks.scale.set(0.5, 0.5);
			add(sparks);
			sparks.cameras = [rankCamera];

			sparksADD.visible = false;
			sparksADD.frames = Paths.getSparrowAtlas('freeplay/sparksadd');
			sparksADD.animation.addByPrefix('sparks add', 'sparks add', 24, false);
			sparksADD.setPosition(498, 116);
			sparksADD.blend = BlendMode.ADD;
			sparksADD.scale.set(0.5, 0.5);
			add(sparksADD);
			sparksADD.cameras = [rankCamera];

			switch (fromResults.oldRank)
			{
				case SHIT:
					sparksADD.color = 0xFF6044FF;
				case GOOD:
					sparksADD.color = 0xFFEF8764;
				case GREAT:
					sparksADD.color = 0xFFEAF6FF;
				case EXCELLENT:
					sparksADD.color = 0xFFFDCB42;
				case PERFECT:
					sparksADD.color = 0xFFFF58B4;
				case PERFECT_GOLD:
					sparksADD.color = 0xFFFFB619;
			}
		}

		curCapsule.doLerp = false;

		originalPos.x = (CUTOUT_WIDTH * SONGS_POS_MULTI) + 320.488;
		originalPos.y = 235.6;

		curCapsule.ranking.visible = false;
		curCapsule.blurredRanking.visible = false;

    	HapticUtil.increasingVibrate(Constants.MIN_VIBRATION_AMPLITUDE, Constants.MAX_VIBRATION_AMPLITUDE, 0.6);

		rankCamera.zoom = 1.85;
		FlxTween.tween(rankCamera, {"zoom": 1.8}, 0.6, {ease: FlxEase.sineIn});

		funnyCam.zoom = 1.15;
		FlxTween.tween(funnyCam, {"zoom": 1.1}, 0.6, {ease: FlxEase.sineIn});

		curCapsule.cameras = [rankCamera];

		curCapsule.initPosition((FlxG.width / 2) - (curCapsule.capsule.width / 2),
			(FlxG.height / 2) - (curCapsule.height / 2));

		new FlxTimer().start(0.5, _ ->
		{
			rankDisplayNew(fromResults);
		});
	}

	function rankDisplayNew(fromResults:Null<FromResultsParams>):Void
	{
		curCapsule.ranking.visible = true;
		curCapsule.blurredRanking.visible = true;
		curCapsule.ranking.scale.set(20, 20);
		curCapsule.blurredRanking.scale.set(20, 20);

		if (fromResults != null && fromResults.newRank != null)
		{
			curCapsule.ranking.animation.play(fromResults.newRank.getFreeplayRankIconAsset(), true);
		}

		FlxTween.tween(curCapsule.ranking, {"scale.x": 1, "scale.y": 1}, 0.1);

		if (fromResults != null && fromResults.newRank != null)
		{
			curCapsule.blurredRanking.animation.play(fromResults.newRank.getFreeplayRankIconAsset(), true);
		}
		FlxTween.tween(curCapsule.blurredRanking, {"scale.x": 1, "scale.y": 1}, 0.1);

		new FlxTimer().start(0.1, _ ->
		{
			if (fromResults?.oldRank != null)
			{
				curCapsule.setFakeRanking(null);

				sparks.visible = true;
				sparksADD.visible = true;
				sparks.animation.play('sparks', true);
				sparksADD.animation.play('sparks add', true);

				sparks.animation.finishCallback = anim ->
				{
					sparks.visible = false;
					sparksADD.visible = false;
				};
			}

			switch (fromResultsParams?.newRank)
			{
				case SHIT:
					FunkinSound.playOnce(Paths.sound('ranks/rankinbad'));
				case PERFECT, PERFECT_GOLD:
					FunkinSound.playOnce(Paths.sound('ranks/rankinperfect'));
				default:
					FunkinSound.playOnce(Paths.sound('ranks/rankinnormal'));
			}
			rankCamera.zoom = 1.3;

			FlxTween.tween(rankCamera, {"zoom": 1.5}, 0.3, {ease: FlxEase.backInOut});

			curCapsule.x -= 10;
			curCapsule.y -= 20;

			FlxTween.tween(funnyCam, {"zoom": 1.05}, 0.3, {ease: FlxEase.elasticOut});

			curCapsule.capsule.angle = -3;
			FlxTween.tween(curCapsule.capsule, {angle: 0}, 0.5, {ease: FlxEase.backOut});

			IntervalShake.shake(curCapsule.capsule, 0.3, 1 / 30, 0.1, 0, FlxEase.quadOut);
		});

		new FlxTimer().start(0.4, _ ->
		{
			FlxTween.tween(funnyCam, {"zoom": 1}, 0.8, {ease: FlxEase.sineIn});
			FlxTween.tween(rankCamera, {"zoom": 1.2}, 0.8, {ease: FlxEase.backIn});
			FlxTween.tween(curCapsule, {x: originalPos.x - 7, y: originalPos.y - 80}, 0.8 + 0.5, {ease: FlxEase.quartIn});
		});

		new FlxTimer().start(0.6, _ ->
		{
			rankAnimSlam(fromResults);
		});
	}

	function rankAnimSlam(fromResultsParams:Null<FromResultsParams>)
	{
		FlxTween.tween(rankBg, {alpha: 0}, 0.5, {ease: FlxEase.expoIn});

		switch (fromResultsParams?.newRank)
		{
			case SHIT:
				FunkinSound.playOnce(Paths.sound('ranks/loss'));
			case GOOD:
				FunkinSound.playOnce(Paths.sound('ranks/good'));
			case GREAT:
				FunkinSound.playOnce(Paths.sound('ranks/great'));
			case EXCELLENT:
				FunkinSound.playOnce(Paths.sound('ranks/excellent'));
			case PERFECT, PERFECT_GOLD:
				FunkinSound.playOnce(Paths.sound('ranks/perfect'));
			default:
				FunkinSound.playOnce(Paths.sound('ranks/loss'));
		}

		FlxTween.tween(curCapsule, {"targetPos.x": originalPos.x, "targetPos.y": originalPos.y}, 0.5, {ease: FlxEase.expoOut});
		new FlxTimer().start(0.5, _ ->
		{
      		HapticUtil.vibrate(Constants.DEFAULT_VIBRATION_PERIOD, Constants.DEFAULT_VIBRATION_DURATION, Constants.MAX_VIBRATION_AMPLITUDE);
			funnyCam.shake(0.0045, 0.35);

			rankCamera.zoom = 0.8;
			funnyCam.zoom = 0.8;
			#if TOUCH_CONTROLS_ALLOWED
			IntervalShake.shake(touchPad, 0.6, 1 / 24, 0.24, 0, FlxEase.quadOut);
			#end
			FlxTween.tween(rankCamera, {"zoom": 1}, 1, {ease: FlxEase.elasticOut});
			FlxTween.tween(funnyCam, {"zoom": 1}, 0.8, {ease: FlxEase.elasticOut});

			for (index => capsule in grpCapsules.activeSongItems)
			{
				var distFromSelected:Float = Math.abs(index - curSelected) - 1;

				if (distFromSelected < 5)
				{
					if (index == curSelected)
					{
						FlxTween.cancelTweensOf(capsule);
						capsule.fadeAnim();

						rankVignette.color = capsule.getTrailColor();
						rankVignette.alpha = 1;
						FlxTween.tween(rankVignette, {alpha: 0}, 0.6, {ease: FlxEase.expoOut});

						capsule.doLerp = false;
						capsule.setPosition(originalPos.x, originalPos.y);
						IntervalShake.shake(capsule, 0.6, 1 / 24, 0.12, 0, FlxEase.quadOut, function(_)
						{
							capsule.doLerp = true;
							capsule.cameras = [funnyCam];

							busy = false;
							capsule.sparkle.alpha = 0.7;
							playCurSongPreview(capsule);
						}, null);

						FlxTween.tween(capsule, {angle: 0}, 0.5, {ease: FlxEase.backOut});
					}
					if (index > curSelected || index < curSelected)
					{
						new FlxTimer().start(distFromSelected / 20, _ ->
						{
							capsule.doLerp = false;

							capsule.capsule.angle = FlxG.random.float(-10 + (distFromSelected * 2), 10 - (distFromSelected * 2));
							FlxTween.tween(capsule.capsule, {angle: 0}, 0.5, {ease: FlxEase.backOut});

							IntervalShake.shake(capsule, 0.6, 1 / 24, 0.12 / (distFromSelected + 1), 0, FlxEase.quadOut, function(_)
							{
								capsule.doLerp = true;
							});
						});
					}
				}

				index += 1;
			}
		});

		new FlxTimer().start(2, _ ->
		{
			prepForNewRank = false;
		});
	}

	override function closeSubState()
	{
		super.closeSubState();

		controls.isInSubstate = true;
		#if TOUCH_CONTROLS_ALLOWED
		#if LEGACY_PSYCH
		MusicBeatSubstate.instance = this;
		#else
		backend.MusicBeatSubstate.instance = this;
		#end
		persistentUpdate = true;
		removeTouchPad();
		addTouchPad('UP_DOWN', 'A_B_C_X_Y_F');
		addTouchPadCamera();
		#end
	}

	function tryOpenCharSelect():Void
	{
		if (PlayerRegistry.instance.countUnlockedCharacters() > 1)
		{
			trace('Opening character select!');
		}
		else
		{
			FunkinSound.playOnce(Paths.sound('cancelMenu'));
			return;
		}

		busy = true;
		FunkinSound.playOnce(Paths.sound('confirmMenu'));

		var transitionDelay:Float = currentCharacter.getFreeplayDJData()?.getCharSelectTransitionDelay() ?? 0.25;

		new FlxTimer().start(transitionDelay, _ ->
		{
			transitionToCharSelect();
		});
	}

	function transitionToCharSelect():Void
	{
		var transitionGradient = new FlxSprite(0, 720).loadGraphic(Paths.image('freeplay/transitionGradient'));
		transitionGradient.scale.set(1280, 1);
		transitionGradient.updateHitbox();
		transitionGradient.cameras = [rankCamera];
		exitMoversCharSel.set([transitionGradient], {
			y: -720,
			speed: 0.8,
			wait: 0.1
		});
		add(transitionGradient);
		for (index => capsule in grpCapsules.activeSongItems)
		{
			var distFromSelected:Float = Math.abs(index - curSelected) - 1;
			if (distFromSelected < 5)
			{
				capsule.doLerp = false;
				exitMoversCharSel.set([capsule], {
					y: -250,
					speed: 0.8,
					wait: 0.1
				});
			}
		}
		funnyCam.filtersEnabled = true;

    	fadeShader.fade(1.0, 0.0, 0.8, {ease: FlxEase.quadIn});
		FlxG.sound.music?.fadeOut(0.9, 0);
		new FlxTimer().start(0.9, _ ->
		{
			FlxG.switchState(new CharSelectSubState());
		});
		for (grpSpr in exitMoversCharSel.keys())
		{
			var moveData:Null<MoveData> = exitMoversCharSel.get(grpSpr);
			if (moveData == null)
				continue;

			for (spr in grpSpr)
			{
				if (spr == null)
					continue;

				var funnyMoveShit:MoveData = moveData;

				var moveDataY = funnyMoveShit.y ?? spr.y;
				var moveDataSpeed = funnyMoveShit.speed ?? 0.2;
				var moveDataWait = funnyMoveShit.wait ?? 0.0;

				FlxTween.tween(spr, {y: moveDataY + spr.y}, moveDataSpeed, {ease: FlxEase.backIn});
			}
		}
		#if TOUCH_CONTROLS_ALLOWED
		FlxTween.tween(touchPad, {alpha: 0}, 0.6, {ease: FlxEase.backIn});
		#end
		backingCard?.enterCharSel();
	}

	function enterFromCharSel():Void
	{
		busy = true;
		if (_parentState != null)
			_parentState.persistentDraw = false;

		var transitionGradient = new FlxSprite(0, 720).loadGraphic(Paths.image('freeplay/transitionGradient'));
		transitionGradient.scale.set(1280, 1);
		transitionGradient.updateHitbox();
		transitionGradient.cameras = [rankCamera];
		exitMoversCharSel.set([transitionGradient], {
			y: -720,
			speed: 1.5,
			wait: 0.1
		});
		add(transitionGradient);
		changeDiff(0, true);
		
		funnyCam.filtersEnabled = true;
		fadeShader.fade(0.0, 1.0, 0.8, {ease: FlxEase.quadIn,onComplete: (twn) -> funnyCam.filtersEnabled = false});
		for (grpSpr in exitMoversCharSel.keys())
		{
			var moveData:Null<MoveData> = exitMoversCharSel.get(grpSpr);
			if (moveData == null)
				continue;

			for (spr in grpSpr)
			{
				if (spr == null)
					continue;

				var funnyMoveShit:MoveData = moveData;

				var moveDataY = funnyMoveShit.y ?? spr.y;
				var moveDataSpeed = funnyMoveShit.speed ?? 0.2;
				var moveDataWait = funnyMoveShit.wait ?? 0.0;

				spr.y += moveDataY;
				FlxTween.tween(spr, {y: spr.y - moveDataY}, moveDataSpeed * 1.2, {
					ease: FlxEase.expoOut,
					onComplete: function(_)
					{
						for (index => capsule in grpCapsules.activeSongItems)
						{
							capsule.doLerp = true;
							fromCharSelect = false;
							busy = false;
							albumRoll.applyExitMovers(exitMovers, exitMoversCharSel);
						}
					}
				});
			}
			#if TOUCH_CONTROLS_ALLOWED
			touchPad.alpha = 0;
			#if LEGACY_PSYCH
			FlxTween.tween(touchPad, {alpha: ClientPrefs.controlsAlpha}, 0.8, {ease: FlxEase.backIn});
			#else
			FlxTween.tween(touchPad, {alpha: ClientPrefs.data.controlsAlpha}, 0.8, {ease: FlxEase.backIn});
			#end
			#end
		}
	}

	var touchY:Float = 0;
	var touchX:Float = 0;
	var dxTouch:Float = 0;
	var dyTouch:Float = 0;
	var velTouch:Float = 0;

	var touchTimer:Float = 0;
	var initTouchPos:FlxPoint = new FlxPoint();

	var spamTimer:Float = 0;
	var spamming:Bool = false;

	public var busy:Bool = false;
	var originalPos:FlxPoint = new FlxPoint();
	var hintTimer:Float = 0;

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// ============================================================
		// ระบบ Preview Events ที่ทำงานสอดคล้องกับการเล่นเพลง
		// ============================================================
		if (!busy && !prepForNewRank)
		{
			// Lerp กล้องให้คืนค่ากลับมาแบบนุ่มนวล
			var camLerp = 1 - Math.exp(-elapsed * 3.125);
			funnyCam.zoom = FlxMath.lerp(funnyCam.zoom, 1.0, camLerp);
			rankCamera.zoom = FlxMath.lerp(rankCamera.zoom, 1.0, camLerp);
		}

		if (FlxG.sound.music != null && FlxG.sound.music.playing)
		{
			var curTime:Float = FlxG.sound.music.time;
			
			// แก้ปัญหาเล่นอีเวนต์รอบเดียว: เช็คว่าถ้าเวลาลดลงไปเยอะๆ แสดงว่าเพลงถูกลูปหรือเริ่มใหม่
			if (currentEventIndex > 0 && curTime < previewEvents[currentEventIndex - 1].time - 500) {
				currentEventIndex = 0;
			}

			while (currentEventIndex < previewEvents.length && curTime >= previewEvents[currentEventIndex].time)
			{
				var ev = previewEvents[currentEventIndex];
				
				// ป้องกันจอเด้งรวบยอดทั้งหมดตอนเริ่ม Preview กลางเพลง
				if (curTime - ev.time < 150)
				{
					switch(ev.name)
					{
						case 'Add Camera Zoom':
							var camZ:Float = 0.015;
							var hudZ:Float = 0.03;
							
							if (ev.v1 != null && ev.v1 != '') {
								var p1 = Std.parseFloat(ev.v1);
								if (!Math.isNaN(p1)) camZ = p1;
							}
							if (ev.v2 != null && ev.v2 != '') {
								var p2 = Std.parseFloat(ev.v2);
								if (!Math.isNaN(p2)) hudZ = p2;
							}
							
							funnyCam.zoom += camZ;
							rankCamera.zoom += hudZ;
							
						// คุณสามารถเพิ่ม Event ตัวอื่นๆ ที่ต้องการให้เล่นใน Freeplay ได้ตรงนี้เลย เช่น
						// case 'Play Animation':
						// 	trace("เล่นอนิเมชั่น: " + ev.v1);
					}
				}
				currentEventIndex++;
			}
		}
		// ============================================================

		if (charSelectHint != null)
		{
			hintTimer += elapsed * 2;
			var targetAmt:Float = (Math.sin(hintTimer) + 1) / 2;
			charSelectHint.alpha = FlxMath.lerp(0.3, 0.9, targetAmt);
		}

		if (!busy)
		{
			if (FlxG.keys.justPressed.CONTROL #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonC.justPressed #end)
			{
				persistentUpdate = false;
				#if TOUCH_CONTROLS_ALLOWED
				removeTouchPad();
				#end
				FreeplayHelpers.openGameplayChanges(this);
			}
			else if ((controls.RESET #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonY.justPressed #end) && curSelected != 0)
			{
				persistentUpdate = false;
				var curSng = curCapsule;
				#if TOUCH_CONTROLS_ALLOWED
				removeTouchPad();
				#end

				FreeplayHelpers.openResetScoreState(this, curSng.songData, () ->
				{
					curSng.songData.scoringRank = null;
					intendedScore = 0;
					intendedCompletion = 0;
					curSng.songData.updateIsNewTag();
					curSng.refreshDisplayDifficulty();
				});
				FunkinSound.playOnce(Paths.sound('scrollMenu'), 0.4);
			} 
		}

		if (controls.FAVORITE #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonF.justPressed #end && !busy) 
		{
			var targetSong = curCapsule?.songData;
			if (targetSong != null)
			{
				var realShit:Int = curSelected;
				var isFav = targetSong.toggleFavorite();
				if (isFav)
				{
					curCapsule.favIcon.visible = true;
					curCapsule.favIconBlurred.visible = true;
					curCapsule.favIcon.animation.play('fav');
					curCapsule.favIconBlurred.animation.play('fav');
					FunkinSound.playOnce(Paths.sound('fav'), 1);
					curCapsule.checkClip();
					curCapsule.selected = curCapsule.selected;
					busy = true;

					curCapsule.doLerp = false;
					FlxTween.tween(curCapsule, {y: curCapsule.y - 5}, 0.1, {ease: FlxEase.expoOut});

					FlxTween.tween(curCapsule, {y: curCapsule.y + 5}, 0.1, {
						ease: FlxEase.expoIn,
						startDelay: 0.1,
						onComplete: function(_)
						{
							curCapsule.doLerp = true;
							busy = false;
						}
					});
				}
				else
				{
					curCapsule.favIcon.animation.play('fav', true, true, 9);
					curCapsule.favIconBlurred.animation.play('fav', true, true, 9);
					FunkinSound.playOnce(Paths.sound('unfav'), 1);
					new FlxTimer().start(0.2, _ ->
					{
						curCapsule.favIcon.visible = false;
						curCapsule.favIconBlurred.visible = false;
						curCapsule.checkClip();
					});

					busy = true;
					curCapsule.doLerp = false;
					FlxTween.tween(curCapsule, {y: curCapsule.y + 5}, 0.1, {ease: FlxEase.expoOut});

					FlxTween.tween(curCapsule, {y: curCapsule.y - 5}, 0.1, {
						ease: FlxEase.expoIn,
						startDelay: 0.1,
						onComplete: function(_)
						{
							curCapsule.doLerp = true;
							busy = false;
						}
					});
				}
			}
		}

		if (FlxG.keys.justPressed.HOME && !busy)
		{
			changeSelection(-curSelected);
		}

		if (FlxG.keys.justPressed.END && !busy)
		{
			changeSelection(grpCapsules.countLiving() - curSelected - 1);
		}
		lerpScoreDisplays(elapsed);

		handleInputs(elapsed);
	}

	function lerpScoreDisplays(elapsed:Float):Void
	{
		lerpScore = MathUtil.smoothLerp(lerpScore, intendedScore, elapsed, 0.5);
		lerpCompletion = MathUtil.smoothLerp(lerpCompletion, intendedCompletion, elapsed, 0.5);

		if (Math.isNaN(lerpScore))
		{
			lerpScore = intendedScore;
		}

		if (Math.isNaN(lerpCompletion))
		{
			lerpCompletion = intendedCompletion;
		}

		fp.updateScore(Std.int(lerpScore));

		txtCompletion.text = '${Math.floor(lerpCompletion * 100)}';

		switch (txtCompletion.text.length)
		{
			case 3:
				txtCompletion.offset.x = 10;
			case 2:
				txtCompletion.offset.x = 0;
			case 1:
				txtCompletion.offset.x = -24;
			default:
				txtCompletion.offset.x = 0;
		}
	} 

	function handleInputs(elapsed:Float):Void
	{
		if (busy)
			return;

		var upP:Bool = controls.UI_UP_P #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonUp.justPressed #end;
		var downP:Bool = controls.UI_DOWN_P #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonDown.justPressed #end;
		var accepted:Bool = controls.ACCEPT #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonA.justPressed #end;
		var up = controls.UI_UP #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonUp.pressed #end;
		var down = controls.UI_DOWN #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonDown.pressed #end;
		
		if ((up || down))
		{
			if (spamming)
			{
				if (spamTimer >= 0.07)
				{
					spamTimer = 0;

					if (up)
					{
						changeSelection(-1);
					}
					else
					{
						changeSelection(1);
					}
				}
			}
			else if (spamTimer >= 0.9)
			{
				spamming = true;
			}
			else if (spamTimer <= 0)
			{
				if (up)
				{
					changeSelection(-1);
				}
				else
				{
					changeSelection(1);
				}
			}

			spamTimer += elapsed;
		}
		else
		{
			spamming = false;
			spamTimer = 0;
		}

		#if !html5
		if (FlxG.mouse.wheel != 0)
		{
			changeSelection(-Math.round(FlxG.mouse.wheel));
		}
		#else
		if (FlxG.mouse.wheel < 0)
		{
			changeSelection(-Math.round(FlxG.mouse.wheel / 8));
		}
		else if (FlxG.mouse.wheel > 0)
		{
			changeSelection(-Math.round(FlxG.mouse.wheel / 8));
		}
		#end

		if (controls.UI_LEFT_P || (TouchUtil.overlapsComplex(diffSelLeft) && TouchUtil.justPressed))
		{
			changeDiff(-1);
			rememberedDifficulty = currentDifficulty; 
			if (diffSelLeft != null)
				diffSelLeft.setPress(true);
		}
		if (controls.UI_RIGHT_P || (TouchUtil.overlapsComplex(diffSelRight) && TouchUtil.justPressed))
		{
			changeDiff(1);
			rememberedDifficulty = currentDifficulty; 
			if (diffSelLeft != null)
				diffSelRight.setPress(true);
		}

		if (diffSelLeft != null && diffSelRight != null && TouchUtil.justReleased)
		{
			diffSelRight.setPress(false);
			diffSelLeft.setPress(false);
		}

		if (controls.BACK #if TOUCH_CONTROLS_ALLOWED || touchPad?.buttonB.justPressed #end && !busy)
		{
			busy = true;
			FlxTween.globalManager.clear();
			FlxTimer.globalManager.clear();

			FunkinSound.playOnce(Paths.sound('cancelMenu'));
			FreeplayHelpers.exitFreeplay();

			var longestTimer:Float = 0;
			backingCard?.disappear();

			#if TOUCH_CONTROLS_ALLOWED
			touchPad.forEachAlive(function(button:TouchButton)
			{
				if (button.tag == 'UP' || button.tag == 'DOWN')
					FlxTween.tween(button, {x: button.x - 350}, 1.2, {ease: FlxEase.backOut});
				else
					FlxTween.tween(button, {x: button.x + 450}, 1.2, {ease: FlxEase.backOut});
			});
			#end

			for (grpSpr in exitMovers.keys())
			{
				var moveData:Null<MoveData> = exitMovers.get(grpSpr);
				if (moveData == null)
					continue;

				for (spr in grpSpr)
				{
					if (spr == null)
						continue;

					var funnyMoveShit:MoveData = moveData;

					var moveDataX = funnyMoveShit.x ?? spr.x;
					var moveDataY = funnyMoveShit.y ?? spr.y;
					var moveDataSpeed = funnyMoveShit.speed ?? 0.2;
					var moveDataWait = funnyMoveShit.wait ?? 0.0;

					FlxTween.tween(spr, {x: moveDataX, y: moveDataY}, moveDataSpeed, {ease: FlxEase.expoIn});

					longestTimer = Math.max(longestTimer, moveDataSpeed + moveDataWait);
				}
			}

			for (caps in grpCapsules.activeSongItems)
			{
				caps.playJumpOut();
			}

			if (Type.getClass(_parentState) == MainMenuState)
			{
				_parentState.persistentUpdate = false;
				_parentState.persistentDraw = true;
			}

			new FlxTimer().start(longestTimer, (_) ->
			{
				FlxTransitionableState.skipNextTransIn = true;
				FlxTransitionableState.skipNextTransOut = true;
				if (Type.getClass(_parentState) == MainMenuState)
				{
					FunkinSound.playMusic('freakyMenu', {
						overrideExisting: true,
						restartTrack: false
					});
					FlxG.sound.music.fadeIn(4.0, 0.0, 1.0);
					close();
				}
				else
				{
					FlxG.switchState(new MainMenuState());
				}
			});
		}
		else if (accepted) 
		{
			curCapsule.onConfirm();
		}
	}

	override function beatHit()
	{
		backingCard?.beatHit(curBeat);

		super.beatHit();
	}

	public override function destroy():Void
	{
		controls.isInSubstate = false;
		
		var daSong:Null<FreeplaySongData> = currentFilteredSongs[curSelected];
		if (daSong != null)
		{
			clearDaCache(daSong.songName);
		}
		
		FlxG.cameras.remove(funnyCam);
		instance = null;
		
		super.destroy();
	}

	var difficultyLastChange:Int = 0;
	function changeDiff(change:Int = 0, forceUpdateSongList:Bool = false):Void
	{
		touchTimer = 0;
		difficultyLastChange = change;

		if (diffIdsCurrent == null || diffIdsCurrent.length == 0)
			diffIdsCurrent = diffIdsTotal.copy();

		var currentDifficultyIndex:Int = diffIdsCurrent.indexOf(currentDifficulty);

		if (currentDifficultyIndex == -1)
		{
			for (i in 0...diffIdsCurrent.length)
			{
				if (diffIdsCurrent[i].toLowerCase() == currentDifficulty.toLowerCase())
				{
					currentDifficultyIndex = i;
					currentDifficulty = diffIdsCurrent[i];
					break;
				}
			}
			if (currentDifficultyIndex == -1)
			{
				if (diffIdsCurrent.length > 0)
					currentDifficultyIndex = 0;
				else
					return;
			}
		}

		currentDifficultyIndex += change;
		if (currentDifficultyIndex < 0)
			currentDifficultyIndex = diffIdsCurrent.length - 1;
		if (currentDifficultyIndex >= diffIdsCurrent.length)
			currentDifficultyIndex = 0;

		var didDifficultyChange = currentDifficulty.toLowerCase() != diffIdsCurrent[currentDifficultyIndex].toLowerCase();

		if(didDifficultyChange) {
			busy = true;
			swipeDiffSpr(false,change);
		}
		if(change != 0){
			HapticUtil.vibrate(0, 0.01, 0.5, 0.1);
			FunkinSound.playOnce(Paths.sound('scrollMenu'), 0.4);
		}

		if (diffIdsCurrent.length > 0)
			currentDifficulty = diffIdsCurrent[currentDifficultyIndex];

		var daSong:Null<FreeplaySongData> = curCapsule?.songData;
		if (daSong != null)
		{
			daSong.currentDifficulty = currentDifficulty;
			var diffId = daSong.loadAndGetDiffId(); 
			var songScore:Int = Highscore.getScore(daSong.getNativeSongId(), diffId); 

			intendedScore = songScore ?? 0;
			intendedCompletion = Highscore.getRating(daSong.getNativeSongId(), diffId);
		}
		else
		{
			intendedScore = 0;
			intendedCompletion = 0.0;
		}
		rememberedDifficulty = currentDifficulty;
		if (intendedCompletion == Math.POSITIVE_INFINITY || intendedCompletion == Math.NEGATIVE_INFINITY || Math.isNaN(intendedCompletion))
			intendedCompletion = 0;
		
		if (didDifficultyChange) swipeDiffSpr(true,change);

		if (change != 0 || forceUpdateSongList)
			updateCapsuleDifficulties();

		var newAlbumId:Null<String> = daSong?.albumId;
		if (albumRoll.albumId != newAlbumId)
		{
			albumRoll.albumId = newAlbumId;
			albumRoll.skipIntro();
		}
		albumRoll.setDifficultyStars(daSong?.difficultyRating);

		// อัปเดตตัวละครเมื่อเปลี่ยนความยาก
		updateLeftCharacter();
		
		// อัปเดตไฟล์อีเวนต์ซูมตามความยากใหม่ด้วย
		if (daSong != null)
		{
			loadEventsForPreview(daSong, currentDifficulty);
		}
	}

	function updateCapsuleDifficulties() {
		var tempSongs:Array<Null<FreeplaySongData>> = songs;

		if (currentFilter != null)
			tempSongs = sortSongs(tempSongs, currentFilter);

		if (currentDifficulty != null)
		{
			tempSongs = tempSongs.filter(song ->
			{
				if (song == null)
					return true; 
				for (d in song.songDifficulties)
				{
					if (d != null && d.toLowerCase() == currentDifficulty.toLowerCase())
						return true;
				}
				return false;
			});
		}
		var areSongsTheSame = tempSongs.isEqualUnordered(currentFilteredSongs);

		if(areSongsTheSame)
			grpCapsules.updateSongDifficulties(currentDifficulty);
		else 
			generateSongList(currentFilter, true, false);
	}

	function swipeDiffSpr(transIn:Bool, change:Int)
	{
		var getCurrentDiff = () ->
		{
			for (diffSprite in grpDifficulties.group.members)
			{
				if (diffSprite != null && diffSprite.difficultyId.toLowerCase() == currentDifficulty.toLowerCase())
					return diffSprite;
			}
			return null;
		}

		var diffObj = getCurrentDiff(); 
		if(diffObj == null) return;
		var diffSprite:DifficultySprite = diffObj;

		FlxTween.cancelTweensOf(diffSprite);

		if (transIn)
		{
			diffSprite.visible = true;

			diffSprite.x = (change > 0) ? 500 : -320;
			diffSprite.x += (CUTOUT_WIDTH * DJ_POS_MULTI);

			FlxTween.tween(diffSprite, {x:  diffSprite.widthOffset + (CUTOUT_WIDTH * DJ_POS_MULTI)}, 0.2, {
				ease: FlxEase.circInOut
			});

			diffSprite.offset.y += 5;
			diffSprite.alpha = 0.5;
			new FlxTimer().start(1 / 24, function(swag)
			{
				busy = false;
				diffSprite.alpha = 1;
				diffSprite.updateHitbox();
				diffSprite.visible = true;
				diffSprite.height *= 2.5;
			});
		}
		else
		{
			diffSprite.visible = true;
			final newX:Int = (change > 0) ? -320 : 500;

			FlxTween.tween(diffSprite, {x: newX + (CUTOUT_WIDTH * DJ_POS_MULTI)}, 0.2, {
				ease: FlxEase.circInOut,
				onComplete: function(_)
				{
					diffSprite.x = diffSprite.widthOffset + (CUTOUT_WIDTH * DJ_POS_MULTI);
					diffSprite.visible = false;
				}
			});
		}
	}

	function clearDaCache(actualSongTho:String):Void
	{
		var cacheObj = cast(openfl.Assets.cache, AssetCache);
		@:privateAccess
		var list = cacheObj.sound.keys();
		for (song in list)
		{
			if (song == null)
				continue;
			if (!song.contains(actualSongTho) && song.contains(".partial")) 
			{
				var snd = cacheObj.sound.get(song);
				openfl.Assets.cache.clear(song);
			}
		}
	}

	function capsuleOnConfirmRandom(randomCapsule:SongMenuItem):Void
	{
		busy = true;
		letterSort.inputEnabled = false;

		var availableSongCapsules:Array<SongMenuItem> = grpCapsules.activeSongItems.filter(function(cap:SongMenuItem)
		{
			return cap.alive && cap.songData != null;
		});

		if (availableSongCapsules.length == 0)
		{
			busy = false;
			letterSort.inputEnabled = true;
			FunkinSound.playOnce(Paths.sound('cancelMenu'));
			return;
		}

		var targetSong:SongMenuItem = FlxG.random.getObject(availableSongCapsules);

		curSelected = grpCapsules.activeSongItems.indexOf(targetSong);
		curSelectedFractal = curSelected;
		changeSelection(0); 

		capsuleOnConfirmDefault(targetSong);
	}

	function capsuleOnOpenDefault(cap:SongMenuItem):Void
	{
		if (cap.songData.instVariants != null && cap.songData.instVariants.length > 0 && cap.songData.instVariants[0] != "")
		{
			var instrumentalIds = ["default"].concat(cap.songData.instVariants);
			openInstrumentalList(cap, instrumentalIds);
		}
		else
		{
			capsuleOnConfirmDefault(cap);
		}
	}

	public function getControls():Controls
	{
		return controls;
	}

	function openInstrumentalList(cap:SongMenuItem, instrumentalIds:Array<String>):Void
	{
		busy = true;

		capsuleOptionsMenu = new CapsuleOptionsMenu(this, cap.x + 175, cap.y + 115, instrumentalIds);
		capsuleOptionsMenu.cameras = [funnyCam];
		capsuleOptionsMenu.zIndex = 10000;
		add(capsuleOptionsMenu);

		capsuleOptionsMenu.onConfirm = function(targetInstId:String)
		{
			capsuleOnConfirmDefault(cap, targetInstId);
		};
	}

	var capsuleOptionsMenu:Null<CapsuleOptionsMenu> = null;

	public function cleanupCapsuleOptionsMenu():Void
	{
		this.busy = false;

		if (capsuleOptionsMenu != null)
		{
			remove(capsuleOptionsMenu);
			capsuleOptionsMenu = null;
		}
	}

	function capsuleOnConfirmDefault(cap:SongMenuItem, ?targetInstId:String):Void
	{
		busy = true;
		letterSort.inputEnabled = false;

		PlayState.isStoryMode = false;

		var targetSong = cap.songData;
		if (targetSong == null)
		{
			return;
		}

		var targetDifficultyId:String = currentDifficulty;
		PlayState.storyWeek = cap.songData.levelId;

		PlayState.storyDifficultyColor = FlxColor.GRAY;
		for (diffSprite in grpDifficulties.group.members)
		{
			if (diffSprite == null)
				continue;
			if (diffSprite.difficultyId.toLowerCase() == currentDifficulty.toLowerCase())
			{
				PlayState.storyDifficultyColor = diffSprite.difficultyColor;
				break;
			}
		}

		FunkinSound.playOnce(Paths.sound('confirmMenu'));

		curCapsule.animBox.forcePosition();
		curCapsule.confirm();

		backingCard?.confirm();

		HapticUtil.vibrate(0, 0.01, 0.5);

		new FlxTimer().start(styleData?.getStartDelay(), function(tmr:FlxTimer)
		{
			FreeplayHelpers.moveToPlaystate(this, cap.songData, currentDifficulty, targetInstId);
		});
	}

	function rememberSelection():Void
	{
		if (rememberedSongId != null)
		{
			curSelected = currentFilteredSongs.findIndex(function(song)
			{
				if (song == null)
					return false;
				return song.songId == rememberedSongId;
			});

			if (curSelected == -1)
				curSelected = 0;
			curSelectedFractal = curSelected;
		}

		if (rememberedDifficulty != null && diffIdsTotal.length > 0)
		{
			for (d in diffIdsTotal)
			{
				if (d != null && d.toLowerCase() == rememberedDifficulty.toLowerCase())
				{
					currentDifficulty = d;
					break;
				}
			}
		}
	}

	function changeSelectionFractal(change:Float)
	{
		curSelectedFractal = FlxMath.bound(curSelectedFractal + change, 0, grpCapsules.countLiving() - 1);
		for (index => capsule in grpCapsules.activeSongItems)
		{
			index += 1;

			capsule.selected = index == curSelected + 1;

			var capsuleIndex = index - curSelected;
			var yOffset:Float = 0;

			if (capsuleIndex < 0) yOffset += 50;
			else if (capsuleIndex > 4) yOffset -= 10;

			capsule.targetPos.y = capsule.intendedY(index - curSelectedFractal) - yOffset;
			capsule.targetPos.x = capsule.intendedX(index - curSelectedFractal) + (CUTOUT_WIDTH * SONGS_POS_MULTI);

			if (index < curSelected)
				capsule.targetPos.y -= 100; 
		}
	}

	function changeSelection(change:Int = 0, updateCardPosition:Bool = true):Void
	{
		var prevSelected:Int = curSelected;
		if (updateCardPosition)
			curSelectedFractal = curSelected;
		curSelected += change;

		if (curSelected < 0)
			if (updateCardPosition)
			{
				curSelected = grpCapsules.countLiving() - 1;
				change = 0;
				curSelectedFractal = curSelected;
			}
			else
			{
				curSelected = prevSelected;
				return;
			}
		if (curSelected >= grpCapsules.countLiving())
			if (updateCardPosition)
			{
				curSelected = 0;
				change = 0;
				curSelectedFractal = 0;
			}
			else
			{
				curSelected = prevSelected;
				return;
			}

		if (!prepForNewRank && curSelected != prevSelected){
			HapticUtil.vibrate(0, 0.01, 0.5);
			FunkinSound.playOnce(Paths.sound('scrollMenu'), 0.4);
		}

		var daSongCapsule:SongMenuItem = curCapsule;
		if (daSongCapsule != null && daSongCapsule.songData != null)
		{
			diffIdsCurrent = daSongCapsule.songData.songDifficulties;
			rememberedSongId = daSongCapsule.songData.songId;
			changeDiff();
		}
		else
		{
			intendedScore = 0;
			intendedCompletion = 0.0;
			diffIdsCurrent = diffIdsTotal.copy();
			rememberedSongId = null;
			if (diffIdsTotal.length > 0)
			{
				var match:String = null;
				for (d in diffIdsTotal)
				{
					if (d != null && rememberedDifficulty != null && d.toLowerCase() == rememberedDifficulty.toLowerCase())
					{
						match = d;
						break;
					}
				}
				currentDifficulty = (match != null) ? match : diffIdsTotal[0];
			}
			albumRoll.albumId = null;
		}
		if (updateCardPosition)
			changeSelectionFractal(change);

		if (grpCapsules.countLiving() > 0 && !prepForNewRank)
		{
			if (daSongCapsule != null && daSongCapsule.songData != null)
				FreeplayHelpers.loadDiffsFromWeek(daSongCapsule.songData);

			FlxG.sound.music.pause();
			FlxTimer.wait(FADE_IN_DELAY, playCurSongPreview.bind(daSongCapsule));

			tweenCurSongColor(daSongCapsule);
			if (curCapsule != null) curCapsule.selected = true;
		}
		else if (prepForNewRank)
			tweenCurSongColor(daSongCapsule);

		// อัปเดตตัวละครเมื่อเลื่อนเลือกเพลงใหม่
		updateLeftCharacter();

		#if discord_rpc
		updateDiscordPresence();
		#end
	}

	public function playCurSongPreview(?daSongCapsule:SongMenuItem):Void
	{
		if (daSongCapsule == null)
			daSongCapsule = curCapsule;

		if (curSelected == 0 || daSongCapsule == null || daSongCapsule.songData == null)
		{
			// ล้างข้อมูล Event หากเป็นเพลง Random
			previewEvents = [];
			currentEventIndex = 0;
			
			FunkinSound.playMusic('freeplayRandom', {
				startingVolume: 0.0,
				overrideExisting: true,
				restartTrack: false
			});
			FlxG.sound.music.fadeIn(2, 0, 0.7);
		}
		else
		{
			// ============================================
			// โหลด Data อีเวนต์มาเก็บไว้ตอนเพลงเล่น
			// ============================================
			loadEventsForPreview(daSongCapsule.songData, currentDifficulty);
			
			if (!daSongCapsule.selected)
				return; 
			var potentiallyErect:String = (currentDifficulty.toLowerCase() == "erect") || (currentDifficulty.toLowerCase() == "nightmare") ? "-erect" : "";
			var songData = daSongCapsule.songData;
			ModsHelper.loadModDir(songData.folder);
			FunkinSound.playMusic(daSongCapsule.songData.getNativeSongId(), {
				startingVolume: 0.0,
				overrideExisting: true,
				restartTrack: false,
				pathsFunction: INST,
				suffix: potentiallyErect,
				partialParams: {
					loadPartial: true,
					start: songData.freeplayPrevStart,
					end: songData.freeplayPrevEnd
				},
				onLoad: function()
				{
					var endVolume = FADE_IN_END_VOLUME;
					FlxG.sound.music.fadeIn(FADE_IN_DURATION, FADE_IN_START_VOLUME, endVolume);
					var newBPM = daSongCapsule.songData.songStartingBpm;
					FreeplayHelpers.BPM = newBPM; 
				}
			});
		}
	}

	public function tweenCurSongColor(daSongCapsule:SongMenuItem)
	{ 
		if (Std.isOfType(backingCard, BoyfriendCard))
		{
			var newColor:FlxColor = (curSelected == 0 || daSongCapsule == null || daSongCapsule.songData == null) ? 0xFFFFD863 : daSongCapsule.songData.color;
			var bfCard = cast(backingCard, BoyfriendCard);
			bfCard.colorEngine?.tweenColor(newColor);
		}
	}

	// ==========================================================
	// ฟังก์ชันหลักที่ใช้อ่านไฟล์ Chart และดึง Event ต่างๆ แบบครอบคลุม
	// ==========================================================
	function loadEventsForPreview(songData:FreeplaySongData, diff:String)
	{
		previewEvents = [];
		currentEventIndex = 0;
		if (songData == null) return;
		
		var songFolderId = songData.songId;
		var diffId = diff.toLowerCase();
		if (diffId == 'normal') diffId = '';
		var chartName = songFolderId + (diffId != '' ? '-' + diffId : '');
		
		try 
		{
			var jsonStr:String = null;
			var modFolder = songData.folder;
			
			// ทดลองหาไฟล์ events.json ก่อน (รองรับระบบโฟลเดอร์ Mod และ Game)
			var eventPathModDir = 'mods/' + modFolder + '/data/' + songFolderId + '/events.json';
			var eventPathMods = 'mods/data/' + songFolderId + '/events.json';
			var eventPathAssets = 'assets/data/' + songFolderId + '/events.json';
			
			#if sys
			if (sys.FileSystem.exists(eventPathModDir)) jsonStr = sys.io.File.getContent(eventPathModDir);
			else if (sys.FileSystem.exists(eventPathMods)) jsonStr = sys.io.File.getContent(eventPathMods);
			else if (sys.FileSystem.exists(eventPathAssets)) jsonStr = sys.io.File.getContent(eventPathAssets);
			else 
			{
				// ถ้าหา events.json ไม่เจอ ให้ไปอ่านไฟล์ Chart โดยตรงเลย
				var chartPathModDir = 'mods/' + modFolder + '/data/' + songFolderId + '/' + chartName + '.json';
				var chartPathMods = 'mods/data/' + songFolderId + '/' + chartName + '.json';
				var chartPathAssets = 'assets/data/' + songFolderId + '/' + chartName + '.json';
				
				if (sys.FileSystem.exists(chartPathModDir)) jsonStr = sys.io.File.getContent(chartPathModDir);
				else if (sys.FileSystem.exists(chartPathMods)) jsonStr = sys.io.File.getContent(chartPathMods);
				else if (sys.FileSystem.exists(chartPathAssets)) jsonStr = sys.io.File.getContent(chartPathAssets);
			}
			#end
			
			// เจาะข้อมูล Event ทั้งหมด ออกมาจาก JSON Array
			if (jsonStr != null && jsonStr.length > 0) 
			{
				var parsedJson:Dynamic = haxe.Json.parse(jsonStr);
				var eventsArray:Array<Dynamic> = null;
				
				if (parsedJson.song != null && parsedJson.song.events != null) eventsArray = parsedJson.song.events;
				else if (parsedJson.events != null) eventsArray = parsedJson.events;
				
				if (eventsArray != null) 
				{
					for (eventNode in eventsArray) 
					{
						var time:Float = eventNode[0];
						var eventDetails:Array<Dynamic> = eventNode[1];
						for (detail in eventDetails) 
						{
							var evName:String = detail[0];
							var val1:String = Std.string(detail[1]);
							var val2:String = Std.string(detail[2]);
							
							// โกยเก็บทุกๆ อีเวนต์ลงไปใน Array แบบครอบจักรวาล
							previewEvents.push({time: time, name: evName, v1: val1, v2: val2});
						}
					}
				}
			}
		} catch(e:Dynamic) {}
		
		// กรองลำดับตามเวลาให้ถูกต้อง
		previewEvents.sort(function(a, b) return Std.int(a.time - b.time));
	}

	public static function build(?params:FreeplayStateParams, ?stickers:StickerSubState):MusicBeatState
	{
		var result = new MainMenuState(true);
		result.openSubState(new FreeplayState(params, stickers));
		result.persistentUpdate = false;
		result.persistentDraw = true;
		return result;
	}

	#if discord_rpc
	function updateDiscordPresence()
	{
		var daSongCapsule = curCapsule;
		var isRandom = (curSelected == 0 || daSongCapsule == null || daSongCapsule.songData == null);

		var presenceDetails:String = "In Freeplay";
		var presenceState:String = "";
		var imageKey:String = "";

		if (isRandom)
		{
			presenceState = "Listening to: Random";
			imageKey = "random";
		}
		else
		{
			presenceState = "Listening to: " + daSongCapsule.songData.songName;
			
			if (daSongCapsule.songData.songId != null)
				imageKey = daSongCapsule.songData.songId.toLowerCase();
		}

		DiscordClient.changePresence(presenceDetails, presenceState, imageKey);
	}
	#end
}

typedef SongFilter =
{
	var filterType:FilterType;
	var ?filterData:Dynamic;
}

enum abstract FilterType(String)
{
	public var STARTSWITH;
	public var REGEXP;
	public var FAVORITE;
	public var ALL;
}

typedef ExitMoverData = Map<Array<FlxSprite>, MoveData>;

typedef MoveData =
{
	var ?x:Float;
	var ?y:Float;
	var ?speed:Float;
	var ?wait:Float;
}