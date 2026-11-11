package mikolka.vslice.ui.mainmenu;

import mikolka.vslice.freeplay.FreeplayState;
import options.OptionsState;
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.effects.FlxFlicker;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.math.FlxMath;
import objects.Alphabet; 
import lime.app.Application;

#if !LEGACY_PSYCH
import states.CreditsState;
import states.editors.MasterEditorMenu;
#else
import editors.MasterEditorMenu;
#end

import mikolka.compatibility.VsliceOptions;
using StringTools;

@:access(mikolka.vslice.ui.MainMenuState)
class DesktopMenuState extends FlxBasic
{
    public static var hasVisitedBefore:Bool = false;

    var specialFont:String = "The_Wildeast.ttf";
    var defaultFont:String = "vcr.ttf";
    var optionShit:Array<String> = ['story_mode', 'freeplay', 'credits', 'options'];
    public static var curSelected:Int = 0;
    var selectedSomethin:Bool = false;
    var isEntering:Bool = true; 
    
    var menuItems:FlxTypedGroup<FlxText>;
    var menuBoxes:FlxTypedGroup<FlxSprite>;
    var versionTexts:FlxTypedGroup<FlxText>; 
    var uiPanel:FlxSprite; 
    var logo:FlxSprite;
    
    var yunaChar:FlxSprite; 
    var hintText:FlxText;
    var host:MainMenuState;

    var camLerpX:Float = 0;
    var camLerpY:Float = 0;
    var bgShiftY:Float = 0;
    var floatingTime:Float = 0;
    
    var panelWidth:Float = 500; 
    var spacing:Int = 85;
    var startY:Int = 340;

    var oriDead:Bool = false;
    var isShakingOri:Bool = false;

    var songProgressBarBG:FlxSprite;
    var songProgressBar:FlxSprite;
    var nowPlayingText:FlxText;
    var songTimeText:FlxText; 
    var barWidth:Float = 280;
    
    var stopButton:FlxText;
    var canStopMusic:Bool = true;
    var isMusicCutDialogue:Bool = false;

    var dialogueBox:FlxSprite;
    var nameText:FlxText; 
    var dialogueText:FlxText;
    var dialogueSubText:FlxText;
    var isDialogueActive:Bool = false;
    var isDialogueTweening:Bool = false; 
    var isLeavingState:Bool = false; 
    
    var dialogueSequence:Array<String> = [];
    var highlightSequence:Array<String> = [];
    var dialogueProgress:Int = 0;
    var currentDialogue:String = "";
    var currentHighlight:String = "";
    var dialogueIndex:Int = 0;
    var typeTimer:FlxTimer;
    
    var isAutoDialogue:Bool = false;
    var autoNextTimer:FlxTimer;

    var typeSound:flixel.sound.FlxSound;
    var originalMusicVolume:Float = 1.0;
    var currentVolumeMultiplier:Float = 1.0;
    var musicVolumeTween:FlxTween;
    
    var idleTime:Float = 0;
    var sleepThreshold:Float = 60.0;
    var nextIdleBark:Float = 15.0; 
    public static var isOriSleeping:Bool = false;
    var isShowingSleepWarning:Bool = false;
    var isSecretDialogueActive:Bool = false;

    var sleepBotherCount:Int = 0;
    var isTalkButtonSeized:Bool = false;
    var isMouseSeized:Bool = false;

    var floatTextsGrp:FlxTypedGroup<FlxText>;
    var petProgress:Float = 0;
    var lastPetMouseX:Float = 0;
    var lastPetMouseY:Float = 0;
    var nextPetAllowed:Bool = true;
    var isPettingFace:Bool = false;
    var petReleaseTimer:FlxTimer;

    var mouseTrailGrp:FlxTypedGroup<FlxSprite>;
    var lastMouseX:Float = 0;
    var lastMouseY:Float = 0;

    var animOffsets:Map<String, Array<Float>> = [
        'idle1'     => [0, 0],
        'idlesleep' => [17, -316],
        'talk1'     => [0, 3],
        'talk2'     => [0, 3],
        'talk3'     => [0, 3],
        'huh'       => [0, 0],
        'sleepy'    => [55, 0]
    ];

    var fourthWallDialogues:Array<String> = [
        "Hey... Are you just going to stare at my face? Choose a song already!",
        "Did you go to the bathroom or something? I've been waiting forever~",
        "Hellooooo? Is your computer frozen or what?",
        "If you don't press anything soon, I'm just gonna go to sleep..."
    ];

    var secretDialogueSequence:Array<String> = [
        "Ahhhhh, the secret code, right?",
        "Let me think for a second...",
        "I think I forgot it, hehe~",
        "Just kidding!",
        "The code is 'Burnout'.",
        "But... don't type the word 'yasa', okay?"
    ];

    var oriDialogues:Map<String, Array<Array<String>>> = [
        'story_mode' => [
            ["Are you ready to Learn Their Story?", "I bet you'll be amazed!"]
        ],
        'freeplay' => [
            ["Wanna practice some tunes?", "I won't lose to you on the main stage!"],
            ["Pick your favorite Song right now!", "Let's see what amazing skills you've got today~"]
        ],
        'credits' => [
            ["Meet the awesome team behind LostBloom!", "They worked incredibly hard to bring this world to life."]
        ],
        'options' => [
            ["Need to change some preferences?", "Make sure the game runs perfectly smoothly on your setup~"]
        ]
    ];

    var farewellDialogues:Map<String, Array<String>> = [
        'story_mode' => ["Good luck with the story!", "Please say Hello to Ori for me!"],
        'freeplay'   => ["Let's drop the beat! Show me your perfect score!", "Freeplay is waiting for youuu!"],
        'credits'    => ["Let's give some love to the amazing team!", "You will finally know who made this, hehe~"],
        'options'    => ["Get everything tailored perfectly to your style!", "Configuring settings... Make it cozy for yourself! ~"]
    ];

    public function new(host:MainMenuState) {
        super();
        this.host = host;
        host.add(this);

        host.bg.scrollFactor.set(0, 0); 
        host.bg.scale.set(1.2, 1.2);
        host.bg.updateHitbox();
        host.bg.screenCenter(); 

        if (FlxG.sound.music != null) {
            originalMusicVolume = FlxG.sound.music.volume;
            if (originalMusicVolume <= 0) originalMusicVolume = 1.0;
        }

        sleepThreshold = FlxG.random.float(60.0, 90.0);
        nextIdleBark = FlxG.random.float(15.0, 25.0);

        yunaChar = new FlxSprite(-50, -10); 
        yunaChar.frames = Paths.getSparrowAtlas('Menu/Yuna', 'shared');
        
        yunaChar.animation.addByPrefix('idle1', 'idle1', 24, true);
        yunaChar.animation.addByPrefix('idlesleep', 'idlesleep', 24, true);
        yunaChar.animation.addByPrefix('talk1', 'talk1', 24, true);
        yunaChar.animation.addByPrefix('talk2', 'talk2', 24, true);
        yunaChar.animation.addByPrefix('talk3', 'talk3', 24, true);
        yunaChar.animation.addByPrefix('huh', 'huh', 24, true);
        yunaChar.animation.addByPrefix('sleepy', 'sleeping', 24, false);
        yunaChar.antialiasing = VsliceOptions.ANTIALIASING;
        yunaChar.scale.set(0.9, 0.9); 
        yunaChar.updateHitbox();

        yunaChar.animation.finishCallback = function(name:String) {
            if (name == 'sleepy' && isOriSleeping) {
                playYunaAnim('idlesleep', true);
            } else if (name == 'huh' || name == 'talk1') {
                if (!isOriSleeping && !isDialogueActive && !isPettingFace) {
                    playYunaAnim('idle1', true);
                }
            }
        };

        if (isOriSleeping) {
            currentVolumeMultiplier = 0.20;
            playYunaAnim('idlesleep', true);
        } else {
            currentVolumeMultiplier = 1.0;
            playYunaAnim('idle1', true);
        }
        host.add(yunaChar);
        
        var panelTargetX = FlxG.width - panelWidth - 50;
        uiPanel = new FlxSprite(FlxG.width + 100, 260); 
        uiPanel.makeGraphic(Std.int(panelWidth), 420, FlxColor.BLACK);
        uiPanel.alpha = 0.3; 
        host.add(uiPanel);
        FlxTween.tween(uiPanel, {x: panelTargetX}, 0.6, {ease: FlxEase.cubeOut});

        logo = new FlxSprite(FlxG.width + 300, -100).loadGraphic(Paths.image('MainLogo'));
        logo.setGraphicSize(Std.int(logo.width * 0.65)); 
        logo.updateHitbox();
        host.add(logo);
        FlxTween.tween(logo, {x: 730}, 0.6, {ease: FlxEase.cubeOut, startDelay: 0.2});

        menuBoxes = new FlxTypedGroup<FlxSprite>();
        menuItems = new FlxTypedGroup<FlxText>();
        host.add(menuBoxes);
        host.add(menuItems);

        for (i in 0...optionShit.length) {
            var boxWidth:Int = 400;
            var targetX = (FlxG.width - (panelWidth / 2)) - (boxWidth / 2) - 50;
            var startX = FlxG.width + 300; 
            
            var box:FlxSprite = new FlxSprite(startX, startY + (i * spacing));
            box.makeGraphic(boxWidth, 65, FlxColor.WHITE);
            box.alpha = 0; 
            box.ID = i;
            menuBoxes.add(box);

            var menuItem:FlxText = new FlxText(startX, box.y + 10, boxWidth, optionShit[i].replace('_', ' ').toUpperCase());
            menuItem.setFormat(Paths.font(specialFont), 38, FlxColor.WHITE, CENTER); 
            menuItem.ID = i;
            menuItems.add(menuItem);

            var delay = 0.4 + (i * 0.15);
            FlxTween.tween(box, {x: targetX}, 0.5, {ease: FlxEase.cubeOut, startDelay: delay});
            
            var itemID:Int = i;
            FlxTween.tween(menuItem, {x: targetX}, 0.5, {ease: FlxEase.cubeOut, startDelay: delay, onComplete: function(twn:FlxTween) {
                if (itemID == optionShit.length - 1) {
                    isEntering = false;
                }
            }});
        }

        var barX:Float = (FlxG.width - barWidth) / 2;
        var targetBarY:Float = 50;
        var startBarY:Float = -100;

        songProgressBarBG = new FlxSprite(barX, startBarY).makeGraphic(Std.int(barWidth), 6, FlxColor.BLACK);
        songProgressBarBG.alpha = 0;
        host.add(songProgressBarBG);

        songProgressBar = new FlxSprite(barX, startBarY).makeGraphic(Std.int(barWidth), 6, FlxColor.WHITE);
        songProgressBar.origin.set(0, 0);
        songProgressBar.scale.x = 0;
        songProgressBar.alpha = 0;
        host.add(songProgressBar);

        nowPlayingText = new FlxText(barX - 100, startBarY - 25, barWidth + 200, "NOW PLAYING: See You Someday");
        nowPlayingText.setFormat(Paths.font(defaultFont), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        nowPlayingText.alpha = 0;
        host.add(nowPlayingText);

        songTimeText = new FlxText(barX - 100, startBarY + 12, barWidth + 200, "0:00 / 0:00");
        songTimeText.setFormat(Paths.font(defaultFont), 14, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        songTimeText.alpha = 0;
        host.add(songTimeText);

        stopButton = new FlxText(barX + barWidth + 15, startBarY - 7, 100, "[STOP]");
        stopButton.setFormat(Paths.font(defaultFont), 16, FlxColor.RED, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        stopButton.alpha = 0;
        host.add(stopButton);

        FlxTween.tween(songProgressBarBG, {y: targetBarY, alpha: 0.4}, 1.2, {ease: FlxEase.cubeOut, startDelay: 0.2});
        FlxTween.tween(songProgressBar, {y: targetBarY, alpha: 1}, 1.2, {ease: FlxEase.cubeOut, startDelay: 0.2});
        FlxTween.tween(nowPlayingText, {y: targetBarY - 25, alpha: 0.8}, 1.2, {ease: FlxEase.cubeOut, startDelay: 0.2});
        FlxTween.tween(songTimeText, {y: targetBarY + 12, alpha: 0.8}, 1.2, {ease: FlxEase.cubeOut, startDelay: 0.2});
        FlxTween.tween(stopButton, {y: targetBarY - 7, alpha: 1}, 1.2, {ease: FlxEase.cubeOut, startDelay: 0.2});

        setupVersionText();
        setupDialogueUI();

        mouseTrailGrp = new FlxTypedGroup<FlxSprite>();
        host.add(mouseTrailGrp);

        floatTextsGrp = new FlxTypedGroup<FlxText>();
        host.add(floatTextsGrp);

        changeItem(0);
        FlxG.mouse.visible = true; 
        isMouseSeized = false;

        new FlxTimer().start(1.0, function(tmr:FlxTimer) {
            if (!isOriSleeping && (FlxG.save.data.hasVisitedBeforeYuna == null || FlxG.save.data.hasVisitedBeforeYuna == false)) {
                triggerGreetingDialogue();
            }
        });
    }

    function playYunaAnim(animName:String, force:Bool = false, frameToLink:Int = -1) {
        yunaChar.animation.play(animName, force, false, frameToLink >= 0 ? frameToLink : 0);
        if (animOffsets.exists(animName)) {
            var daOffsets = animOffsets.get(animName);
            yunaChar.offset.set(daOffsets[0], daOffsets[1]);
        } else {
            yunaChar.offset.set(0, 0);
        }
    }

    function setupVersionText() {
        versionTexts = new FlxTypedGroup<FlxText>();
        host.add(versionTexts);
        var vTexts:Array<String> = [
            'v${MainMenuState.funkinVersion}',
            "Mow Engine " + MainMenuState.MowVersion,
            "Psych Engine " + MainMenuState.psychEngineVersion,
            "Lost Bloom " + MainMenuState.LostVersion
        ];
        for (i in 0...vTexts.length) {
            var txt = new FlxText(12, FlxG.height - 24 - (i * 20), 0, vTexts[i]);
            txt.setFormat(Paths.font(defaultFont), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            versionTexts.add(txt);
        }

        hintText = new FlxText(0, FlxG.height - 24, FlxG.width - 12, "Press 'H' to Talk or Pet Yuna (Click & Drag)");
        hintText.setFormat(Paths.font(defaultFont), 16, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        hintText.alpha = 0.6;
        host.add(hintText);
    }

    function setupDialogueUI() {
        dialogueBox = new FlxSprite(45, FlxG.height - 235).makeGraphic(650, 180, FlxColor.BLACK);
        dialogueBox.alpha = 0;
        dialogueBox.scale.y = 0; 
        host.add(dialogueBox);

        nameText = new FlxText(65, FlxG.height - 225, 200, "Yuna");
        nameText.setFormat(Paths.font(defaultFont), 22, FlxColor.YELLOW, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        nameText.alpha = 0;
        host.add(nameText);

        dialogueText = new FlxText(70, FlxG.height - 190, 600, "");
        dialogueText.setFormat(Paths.font(defaultFont), 26, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        dialogueText.applyMarkup("", [new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.YELLOW, true), "<yellow>")]);
        dialogueText.alpha = 0;
        host.add(dialogueText);

        dialogueSubText = new FlxText(70, FlxG.height - 190, 600, "");
        dialogueSubText.setFormat(Paths.font(defaultFont), 26, FlxColor.YELLOW, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        dialogueSubText.alpha = 0;
        host.add(dialogueSubText);

        typeSound = new flixel.sound.FlxSound().loadEmbedded(Paths.sound('BunBunTxt'));
        typeSound.volume = 0.45;
        FlxG.sound.list.add(typeSound);
    }

    function resetNamePlate() {
        nameText.text = "Yuna";
        nameText.color = FlxColor.YELLOW;
    }

    function triggerGreetingDialogue() {
        isDialogueActive = true;
        isDialogueTweening = true;
        isAutoDialogue = true; 
        dialogueProgress = 0;

        resetNamePlate();
        dialogueSequence = [
            "Hello there! Welcome to Lost Bloom!",
            "I'm Yuna, and I'll be your guide here.",
            "Take your time and look around~"
        ];
        
        FlxG.save.data.hasVisitedBeforeYuna = true;
        FlxG.save.flush();

        highlightSequence = ["", "", ""];

        versionTexts.forEach(function(txt:FlxText) { txt.alpha = 0; });
        if (musicVolumeTween != null) musicVolumeTween.cancel();
        musicVolumeTween = FlxTween.tween(this, {currentVolumeMultiplier: 0.3}, 0.5);

        playYunaAnim('talk1', true);
        
        dialogueBox.scale.y = 0;
        dialogueBox.alpha = 0;
        FlxTween.tween(dialogueBox, {alpha: 0.75, "scale.y": 1}, 0.35, {ease: FlxEase.backOut, onComplete: function(twn:FlxTween) {
            isDialogueTweening = false;
            nameText.alpha = 1; 
            displayDialogueStep();
        }});
    }

    function hideMouseWithAnimation() {
        if (!FlxG.mouse.visible) return;
        
        FlxG.mouse.visible = false; 
        isMouseSeized = true; 
        
        var mouseAnim:FlxSprite = new FlxSprite(FlxG.mouse.x, FlxG.mouse.y);
        mouseAnim.makeGraphic(12, 12, FlxColor.WHITE); 
        mouseAnim.origin.set(mouseAnim.width / 2, mouseAnim.height / 2);
        host.add(mouseAnim); 
        
        FlxTween.tween(mouseAnim, { "scale.x": 0, "scale.y": 0, angle: 720, alpha: 0 }, 0.5, {
            ease: FlxEase.cubeIn,
            onComplete: function(twn:FlxTween) {
                mouseAnim.kill();
                mouseAnim.destroy();
            }
        });
    }

    override function update(elapsed:Float) {
        floatingTime += elapsed;
        var lerpVal:Float = FlxMath.bound(elapsed * 2, 0, 1); 
        
        if (FlxG.mouse.visible && !isEntering && !isMouseSeized) {
            var distanceMoved = Math.abs(FlxG.mouse.x - lastMouseX) + Math.abs(FlxG.mouse.y - lastMouseY);
            if (distanceMoved > 15) { 
                spawnMouseParticle();
                lastMouseX = FlxG.mouse.x;
                lastMouseY = FlxG.mouse.y;
            }
        }

        if (!selectedSomethin) {
            camLerpX = FlxMath.lerp(camLerpX, Math.sin(floatingTime * 0.8) * 1.2, lerpVal);
            camLerpY = FlxMath.lerp(camLerpY, Math.cos(floatingTime * 0.5) * 1.2, lerpVal);
            bgShiftY = FlxMath.lerp(bgShiftY, curSelected * 2, lerpVal * 0.2);
            if (logo != null) {
                logo.angle = Math.sin(floatingTime * 1.5) * 3.5;
                logo.offset.set(camLerpX * 2, camLerpY * 2);
            }

            if (yunaChar != null && yunaChar.animation.curAnim != null) {
                var currentAnimName = yunaChar.animation.curAnim.name;
                var baseOffsetX:Float = 0;
                var baseOffsetY:Float = 0;
                if (animOffsets.exists(currentAnimName)) {
                    baseOffsetX = animOffsets.get(currentAnimName)[0];
                    baseOffsetY = animOffsets.get(currentAnimName)[1];
                }
                yunaChar.offset.set(baseOffsetX + (camLerpX * 0.5), baseOffsetY + (camLerpY * 0.5));
            }
        }

        if (FlxG.sound.music != null) {
            FlxG.sound.music.volume = originalMusicVolume * currentVolumeMultiplier;
            
            if (FlxG.sound.music.playing && FlxG.sound.music.length > 0) {
                var ratio:Float = FlxG.sound.music.time / FlxG.sound.music.length;
                songProgressBar.scale.x = FlxMath.bound(ratio, 0, 1);

                var curSecs:Int = Std.int(Math.max(0, FlxG.sound.music.time / 1000));
                var maxSecs:Int = Std.int(Math.max(0, FlxG.sound.music.length / 1000));

                var curMin:Int = Std.int(curSecs / 60);
                var curSec:Int = curSecs % 60;
                var maxMin:Int = Std.int(maxSecs / 60);
                var maxSec:Int = maxSecs % 60;

                var curSecStr:String = (curSec < 10) ? "0" + curSec : "" + curSec;
                var maxSecStr:String = (maxSec < 10) ? "0" + maxSec : "" + maxSec;

                songTimeText.text = curMin + ":" + curSecStr + " / " + maxMin + ":" + maxSecStr;
            } else if (!isMusicCutDialogue) {
                songProgressBar.scale.x = 0;
            }
        }

        if (isShakingOri && !oriDead) {
            yunaChar.offset.x += FlxG.random.float(-10, 10);
        }

        if (!selectedSomethin && !oriDead && !isDialogueTweening && !isEntering) {
            var anyInput:Bool = false;
            
            if (FlxG.mouse.pressed && FlxG.mouse.overlaps(yunaChar) && !isDialogueActive && !isMouseSeized) {
                var petDistanceMoved = Math.abs(FlxG.mouse.x - lastPetMouseX) + Math.abs(FlxG.mouse.y - lastPetMouseY);
                
                if (petDistanceMoved > 2) {
                    anyInput = true;
                    if (isOriSleeping) {
                        hideMouseWithAnimation();
                        isMouseSeized = true;
                        showFloatingText("Don't poke her!", FlxColor.RED);
                    } else {
                        petProgress += elapsed;
                        
                        if (petReleaseTimer != null && petReleaseTimer.active) petReleaseTimer.cancel();
                        
                        isPettingFace = true;
                        playYunaAnim('talk2', false);
                        freezeYunaAtFrame(10);
                        
                        if (FlxG.random.bool(15)) spawnHeartParticle();

                        if (petProgress > 0.6 && nextPetAllowed) { 
                            petProgress = 0;
                            nextPetAllowed = false;
                            triggerHappyPetReaction();
                            new FlxTimer().start(1.5, function(tmr:FlxTimer) { nextPetAllowed = true; });
                        }
                    }
                }
                lastPetMouseX = FlxG.mouse.x;
                lastPetMouseY = FlxG.mouse.y;
            } else {
                if (isPettingFace) {
                    isPettingFace = false;
                    petReleaseTimer = new FlxTimer().start(2.0, function(tmr:FlxTimer) {
                        if (!isDialogueActive && !isOriSleeping) {
                            playYunaAnim('idle1', true);
                            if (yunaChar.animation.curAnim != null) yunaChar.animation.curAnim.paused = false;
                        }
                    });
                }
                petProgress = 0;
                lastPetMouseX = FlxG.mouse.x;
                lastPetMouseY = FlxG.mouse.y;
            }

            if (FlxG.mouse.justPressed && FlxG.mouse.overlaps(stopButton) && !isMouseSeized) {
                anyInput = true;
                if (isOriSleeping) {
                    if (FlxG.sound.music != null) {
                        if (FlxG.sound.music.playing) {
                            FlxG.sound.music.pause();
                            stopButton.text = "[PLAY]";
                        } else {
                            FlxG.sound.music.play();
                            stopButton.text = "[STOP]";
                        }
                    }
                    showFloatingText("I think she is asleep now...", FlxColor.GRAY);
                } else if (canStopMusic) {
                    hideMouseWithAnimation();
                    isMouseSeized = true;
                    triggerMusicStopEvent();
                }
            }

            if (FlxG.keys.justPressed.SEVEN) {
                anyInput = true;
                MusicBeatState.switchState(new MasterEditorMenu());
            }
            
            // --- ระบบปุ่ม H ที่แก้ไขแก้ Softlock ---
            if (FlxG.keys.justPressed.H && !isAutoDialogue) {
                anyInput = true;
                
                if (isDialogueActive) {
                    // ถ้ากำลังคุยอยู่หรือมีข้อความค้างอยู่ ให้กดข้าม/ปิดกล่องข้อความได้เสมอ
                    checkDialogueProgress();
                } else {
                    // ถ้ายังไม่มีข้อความ ค่อยเช็คเงื่อนไขต่างๆ
                    if (isTalkButtonSeized) {
                        showFloatingText("Ori locked the Talk button...", FlxColor.GRAY);
                    } else {
                        if (isOriSleeping) {
                            showSleepWarning();
                        } else {
                            if (states.CreditsState.failedCode) {
                                startSecretDialogue();
                            } else {
                                startDialogue();
                            }
                        }
                    }
                }
            }

            if (!isDialogueActive) {
                if (host.controls.UI_UP_P) {
                    anyInput = true;
                    changeSelection(curSelected - 1);
                }
                if (host.controls.UI_DOWN_P) {
                    anyInput = true;
                    changeSelection(curSelected + 1);
                }
                
                if (!isMouseSeized) {
                    for (i in 0...menuBoxes.length) {
                        var box = menuBoxes.members[i];
                        if (FlxG.mouse.overlaps(box)) {
                            if (curSelected != box.ID) changeSelection(box.ID); 
                            if (FlxG.mouse.justPressed) {
                                anyInput = true;
                                hideMouseWithAnimation();
                                isMouseSeized = true;
                                selectItem(); 
                            }
                        }
                    }
                }

                if (host.controls.ACCEPT) {
                    anyInput = true;
                    hideMouseWithAnimation();
                    isMouseSeized = true;
                    selectItem(); 
                }
            }

            if (anyInput) {
                idleTime = 0;
                nextIdleBark = FlxG.random.float(15.0, 25.0);
            } else {
                if (!isDialogueActive) {
                    idleTime += elapsed;
                    if (idleTime >= nextIdleBark && !isOriSleeping) {
                        nextIdleBark += FlxG.random.float(20.0, 30.0);
                        triggerFourthWallDialogue();
                    }
                    else if (idleTime >= sleepThreshold && !isOriSleeping) { 
                        goAsleep();
                    }
                }
            }
        }
        super.update(elapsed);
    }

    function spawnMouseParticle() {
        var particle:FlxSprite = new FlxSprite(FlxG.mouse.x - 4, FlxG.mouse.y - 4);
        particle.makeGraphic(8, 8, FlxColor.WHITE);
        particle.color = FlxColor.YELLOW;
        particle.angle = FlxG.random.float(0, 360);
        particle.alpha = 0.8;
        mouseTrailGrp.add(particle);

        FlxTween.tween(particle, {
            y: particle.y + FlxG.random.float(15, 35), 
            alpha: 0, 
            angle: particle.angle + 120
        }, 0.5, {
            ease: FlxEase.quadOut,
            onComplete: function(twn:FlxTween) {
                particle.kill();
                mouseTrailGrp.remove(particle, true);
                particle.destroy();
            }
        });
    }

    function spawnHeartParticle() {
        var heart:FlxText = new FlxText(FlxG.mouse.x - 10, FlxG.mouse.y - 10, 0, "♥");
        heart.setFormat(Paths.font(defaultFont), 18, FlxColor.PINK, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        mouseTrailGrp.add(heart);

        FlxTween.tween(heart, {
            y: heart.y - FlxG.random.float(20, 40), 
            x: heart.x + FlxG.random.float(-15, 15),
            alpha: 0
        }, 0.8, {
            ease: FlxEase.cubeOut,
            onComplete: function(twn:FlxTween) {
                heart.kill();
                mouseTrailGrp.remove(heart, true);
                heart.destroy();
            }
        });
    }

    function triggerHappyPetReaction() {
        if (isOriSleeping) return;
        var happyLines:Array<String> = ["Hehe~", "*happy fox squeaks*", "That feels so nice~", "Yip! ♥", "You're so sweet~", "Keep going, please~"];
        showFloatingText(FlxG.random.getObject(happyLines), 0xFFFFA2D7); 
    }

    function showFloatingText(text:String, color:FlxColor = FlxColor.YELLOW) {
        var floatTxt:FlxText = new FlxText(yunaChar.x + 180, yunaChar.y + 100, 0, text);
        floatTxt.setFormat(Paths.font(defaultFont), 24, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        floatTextsGrp.add(floatTxt);

        FlxTween.tween(floatTxt, {y: floatTxt.y - 60, alpha: 0}, 1.5, {
            ease: FlxEase.cubeOut,
            onComplete: function(twn:FlxTween) {
                floatTxt.kill();
                floatTextsGrp.remove(floatTxt, true);
                floatTxt.destroy();
            }
        });
    }

    function triggerFourthWallDialogue() {
        isDialogueActive = true;
        isDialogueTweening = true;
        isAutoDialogue = true; 
        dialogueProgress = 0;

        resetNamePlate();
        dialogueSequence = [FlxG.random.getObject(fourthWallDialogues)];
        highlightSequence = [""];

        versionTexts.forEach(function(txt:FlxText) { txt.alpha = 0; });
        if (musicVolumeTween != null) musicVolumeTween.cancel();
        musicVolumeTween = FlxTween.tween(this, {currentVolumeMultiplier: 0.3}, 0.5);

        playYunaAnim('talk' + FlxG.random.int(1, 3), true);
        
        dialogueBox.scale.y = 0;
        dialogueBox.alpha = 0;
        FlxTween.tween(dialogueBox, {alpha: 0.75, "scale.y": 1}, 0.35, {ease: FlxEase.backOut, onComplete: function(twn:FlxTween) {
            isDialogueTweening = false;
            nameText.alpha = 1; 
            displayDialogueStep();
        }});
    }

    function triggerMusicStopEvent() {
        canStopMusic = false; 
        if (FlxG.sound.music != null) FlxG.sound.music.pause();
        
        isDialogueActive = true;
        isDialogueTweening = true;
        isMusicCutDialogue = true;
        isAutoDialogue = true; 
        dialogueProgress = 0;

        resetNamePlate();
        dialogueSequence = [
            "Why did you stop the music...?",
            "Let's listen to it together, please!",
            "I won't let you turn it off again! Button locked, hehe~"
        ];
        highlightSequence = ["", "", ""];

        versionTexts.forEach(function(txt:FlxText) { txt.alpha = 0; });
        if (musicVolumeTween != null) musicVolumeTween.cancel();

        playYunaAnim('huh', true);

        dialogueBox.scale.y = 0;
        dialogueBox.alpha = 0;
        FlxTween.tween(dialogueBox, {alpha: 0.75, "scale.y": 1}, 0.35, {ease: FlxEase.backOut, onComplete: function(twn:FlxTween) {
            isDialogueTweening = false;
            nameText.alpha = 1; 
            displayDialogueStep();
        }});
    }

    function getHighlightX():Float {
        var cleanString = dialogueText.text.replace("<yellow>", "").replace("</yellow>", "");
        var textLength:Float = cleanString.length * 16;
        var maxLimit:Float = dialogueText.width - 200;
        return dialogueText.x + (textLength < maxLimit ? textLength : maxLimit);
    }

    function freezeYunaAtFrame(frameIndex:Int) {
        if (yunaChar.animation.curAnim != null) {
            yunaChar.animation.curAnim.paused = true;
            yunaChar.animation.curAnim.curFrame = frameIndex;
        }
    }

    function goAsleep() {
        isOriSleeping = true;
        if (musicVolumeTween != null) musicVolumeTween.cancel();
        musicVolumeTween = FlxTween.tween(this, {currentVolumeMultiplier: 0.20}, 1.5);
        playYunaAnim('sleepy', true);
    }

    function wakeOriUp() {
        isOriSleeping = false;
        idleTime = 0;
        sleepBotherCount = 0;      
        isTalkButtonSeized = false;
        sleepThreshold = FlxG.random.float(60.0, 90.0); 
        
        if (musicVolumeTween != null) musicVolumeTween.cancel();
        musicVolumeTween = FlxTween.tween(this, {currentVolumeMultiplier: 1.0}, 0.8);
        
        playYunaAnim('idle1', true);
    }

    function showSleepWarning() {
        isDialogueActive = true;
        isDialogueTweening = true;
        isShowingSleepWarning = true;
        isSecretDialogueActive = false;
        isAutoDialogue = false; 
        dialogueProgress = 0;

        sleepBotherCount++;
        
        var speaker:String = "";
        var dialogueLine:String = "";

        if (sleepBotherCount >= 4) {
            speaker = "Ori (TP-01)";
            dialogueLine = "That's it. I'm taking your talk button. Let her sleep.";
            isTalkButtonSeized = true;
        } else {
            if (FlxG.random.bool(50)) {
                speaker = "Kane";
                var kaneLines = [
                    "Shh... Yuna is dreaming right now!", 
                    "Let her rest a bit, alright? She's tired.", 
                    "Hey there! Let's keep it quiet for now~"
                ];
                dialogueLine = FlxG.random.getObject(kaneLines);
            } else {
                speaker = "Ori (TP-01)";
                var oriLines = [
                    "Ugh... she's asleep. Stop clicking.", 
                    "Can't you see she's resting? I'm tired too... *yawn*", 
                    "Stop pressing buttons... it's annoying."
                ];
                dialogueLine = FlxG.random.getObject(oriLines);
            }
        }

        nameText.text = speaker;
        if (speaker == "Kane") {
            nameText.color = FlxColor.CYAN; 
        } else {
            nameText.color = 0xFFAAAAAA; 
        }

        dialogueSequence = [dialogueLine];
        highlightSequence = [""];

        versionTexts.forEach(function(txt:FlxText) { txt.alpha = 0; });

        dialogueBox.scale.y = 0;
        dialogueBox.alpha = 0;
        FlxTween.tween(dialogueBox, {alpha: 0.75, "scale.y": 1}, 0.35, {ease: FlxEase.backOut, onComplete: function(twn:FlxTween) {
            isDialogueTweening = false;
            nameText.alpha = 1; 
            displayDialogueStep();
        }});
    }

    function startSecretDialogue() {
        isDialogueActive = true;
        isDialogueTweening = true;
        isSecretDialogueActive = true;
        dialogueProgress = 0;

        resetNamePlate();
        dialogueSequence = [];
        highlightSequence = [];
        for(line in secretDialogueSequence) {
            dialogueSequence.push(line);
            highlightSequence.push("");
        }

        versionTexts.forEach(function(txt:FlxText) { txt.alpha = 0; }); 

        if (musicVolumeTween != null) musicVolumeTween.cancel();
        musicVolumeTween = FlxTween.tween(this, {currentVolumeMultiplier: 0.3}, 0.5);

        playYunaAnim('talk1', true); 

        dialogueBox.scale.y = 0;
        dialogueBox.alpha = 0;
        FlxTween.tween(dialogueBox, {alpha: 0.75, "scale.y": 1}, 0.35, {ease: FlxEase.backOut, onComplete: function(twn:FlxTween) {
            isDialogueTweening = false;
            nameText.alpha = 1; 
            displayDialogueStep();
        }});
    }

    function startDialogue() {
        isDialogueActive = true;
        isDialogueTweening = true;
        isSecretDialogueActive = false;
        dialogueProgress = 0;
        dialogueSequence = [];
        highlightSequence = [];

        resetNamePlate();

        var targetPool = oriDialogues.get(optionShit[curSelected]);
        var pickedDialogue = FlxG.random.getObject(targetPool);
        for (i in 0...pickedDialogue.length) {
            var rawStr:String = pickedDialogue[i];
            if (rawStr.contains("|")) {
                var parts = rawStr.split("|");
                dialogueSequence.push(parts[0]);
                highlightSequence.push(parts[1]);
            } else {
                dialogueSequence.push(rawStr);
                highlightSequence.push("");
            }
        }

        versionTexts.forEach(function(txt:FlxText) { txt.alpha = 0; });
        if (musicVolumeTween != null) musicVolumeTween.cancel();
        musicVolumeTween = FlxTween.tween(this, {currentVolumeMultiplier: 0.3}, 0.5);

        var randTalk = FlxG.random.int(1, 3);
        playYunaAnim('talk' + randTalk, true); 

        dialogueBox.scale.y = 0;
        dialogueBox.alpha = 0;
        FlxTween.tween(dialogueBox, {alpha: 0.75, "scale.y": 1}, 0.35, {ease: FlxEase.backOut, onComplete: function(twn:FlxTween) {
            isDialogueTweening = false;
            nameText.alpha = 1; 
            displayDialogueStep();
        }});
    }

    function playFarewellDialogue() {
        isDialogueActive = true;
        isDialogueTweening = true;
        isLeavingState = true;
        isSecretDialogueActive = false;

        resetNamePlate();
        versionTexts.forEach(function(txt:FlxText) { txt.alpha = 0; });

        var shiftDistance:Float = 600; 
        var duration:Float = 0.55;
        var slideEase = FlxEase.backIn;

        FlxTween.tween(uiPanel, {x: uiPanel.x + shiftDistance, alpha: 0}, duration, {ease: slideEase});
        FlxTween.tween(logo, {x: logo.x + shiftDistance, alpha: 0}, duration, {ease: slideEase});
        FlxTween.tween(hintText, {alpha: 0}, 0.2);

        FlxTween.tween(songProgressBarBG, {alpha: 0}, duration, {ease: slideEase});
        FlxTween.tween(songProgressBar, {alpha: 0}, duration, {ease: slideEase});
        FlxTween.tween(nowPlayingText, {alpha: 0}, duration, {ease: slideEase});
        FlxTween.tween(songTimeText, {alpha: 0}, duration, {ease: slideEase});
        FlxTween.tween(stopButton, {alpha: 0}, duration, {ease: slideEase});

        menuBoxes.forEach(function(box:FlxSprite) {
            FlxTween.tween(box, {x: box.x + shiftDistance}, duration, {ease: slideEase});
        });
        menuItems.forEach(function(txt:FlxText) {
            FlxTween.tween(txt, {x: txt.x + shiftDistance}, duration, {ease: slideEase});
        });
        
        var randTalk = FlxG.random.int(1, 3);
        playYunaAnim('talk' + randTalk, true);

        var choice = optionShit[curSelected];
        var farewellPool = farewellDialogues.get(choice);
        currentDialogue = FlxG.random.getObject(farewellPool);
        currentHighlight = "";
        dialogueIndex = 0;

        dialogueText.text = "";
        dialogueSubText.text = "";

        dialogueBox.scale.y = 0;
        dialogueBox.alpha = 0;
        FlxTween.tween(dialogueBox, {alpha: 0.75, "scale.y": 1}, 0.3, {ease: FlxEase.backOut, onComplete: function(twn:FlxTween) {
            isDialogueTweening = false;
            nameText.alpha = 1; 
            dialogueText.alpha = 1;

            if (typeTimer != null) typeTimer.cancel();
            typeTimer = new FlxTimer().start(0.04, function(tmr:FlxTimer) {
                if (dialogueIndex < currentDialogue.length) {
                    var nextChar:String = currentDialogue.charAt(dialogueIndex);
                    dialogueText.text += nextChar;
                    dialogueIndex++;
                    if (nextChar != " " && typeSound != null) typeSound.play(true);
                } else {
                    tmr.cancel();
                    freezeYunaAtFrame(8); 

                    new FlxTimer().start(1.0, function(delayTmr:FlxTimer) {
                        nameText.alpha = 0;
                        dialogueText.alpha = 0;
                        FlxTween.tween(dialogueBox, {alpha: 0, "scale.y": 0}, 0.2, {ease: FlxEase.quadIn, onComplete: function(twn:FlxTween) {
                            executeStateChange();
                        }});
                    });
                }
            }, 0);
        }});
    }

    function displayDialogueStep() {
        currentDialogue = dialogueSequence[dialogueProgress];
        currentHighlight = highlightSequence[dialogueProgress];
        dialogueIndex = 0;
        
        dialogueText.clearFormats(); 
        dialogueText.text = "";
        dialogueSubText.text = "";
        dialogueText.alpha = 1;
        dialogueSubText.alpha = 1;

        if (typeTimer != null) typeTimer.cancel();
        typeTimer = new FlxTimer().start(0.04, typeLetter, 0);
    }

    function typeLetter(tmr:FlxTimer) {
        if (dialogueIndex < currentDialogue.length) {
            var nextChar:String = currentDialogue.charAt(dialogueIndex);
            dialogueText.text += nextChar;
            dialogueIndex++;

            if (nextChar != " ") {
                if (typeSound != null) {
                    typeSound.play(true);
                }
            }
        } else {
            tmr.cancel();
            freezeYunaAtFrame(10);

            if (currentHighlight != "") {
                dialogueSubText.x = getHighlightX();
                dialogueSubText.text = currentHighlight;
            }

            if (isAutoDialogue) {
                if (autoNextTimer != null) autoNextTimer.cancel();
                autoNextTimer = new FlxTimer().start(2.5, function(tmr2:FlxTimer) {
                    checkDialogueProgress();
                });
            }
        }
    }

    function checkDialogueProgress() {
        if (isLeavingState) return;
        if (dialogueIndex < currentDialogue.length) {
            if (typeTimer != null) typeTimer.cancel();
            dialogueText.clearFormats();
            dialogueText.text = currentDialogue;
            dialogueIndex = currentDialogue.length;
            freezeYunaAtFrame(10);
            if (currentHighlight != "") {
                dialogueSubText.x = getHighlightX();
                dialogueSubText.text = currentHighlight;
            }

            if (isAutoDialogue) {
                if (autoNextTimer != null) autoNextTimer.cancel();
                autoNextTimer = new FlxTimer().start(2.5, function(tmr2:FlxTimer) {
                    checkDialogueProgress();
                });
            }
        } else {
            dialogueProgress++;
            if (dialogueProgress < dialogueSequence.length) {
                var randTalk = FlxG.random.int(1, 3);
                playYunaAnim('talk' + randTalk, true);
                displayDialogueStep();
            } else {
                if (autoNextTimer != null) autoNextTimer.cancel();

                if(isSecretDialogueActive) {
                    states.CreditsState.failedCode = false;
                    isSecretDialogueActive = false;
                }
                
                if (isMusicCutDialogue) {
                    isMusicCutDialogue = false;
                    isAutoDialogue = false; 
                    stopButton.text = "[LOCKED]";
                    stopButton.color = FlxColor.GRAY;
                    if (FlxG.sound.music != null) FlxG.sound.music.play();
                } else if (isAutoDialogue) {
                    isAutoDialogue = false; 
                }
                
                closeDialogue(); 
            }
        }
    }

    function closeDialogue() {
        isDialogueActive = false;
        isDialogueTweening = true;
        isShowingSleepWarning = false;
        if (autoNextTimer != null) autoNextTimer.cancel(); 

        nameText.alpha = 0; 
        dialogueText.alpha = 0;
        dialogueSubText.alpha = 0;
        FlxTween.tween(dialogueBox, {alpha: 0, "scale.y": 0}, 0.25, {ease: FlxEase.quadIn, onComplete: function(twn:FlxTween) {
            isDialogueTweening = false;
            versionTexts.forEach(function(txt:FlxText) { txt.alpha = 1; }); 

            if (!isOriSleeping) {
                if (musicVolumeTween != null) musicVolumeTween.cancel();
                musicVolumeTween = FlxTween.tween(this, {currentVolumeMultiplier: 1.0}, 0.5);
                playYunaAnim('idle1', true); 
            } else {
                playYunaAnim('idlesleep', true);
            }
        }});
    }

    function changeItem(huh:Int = 0) {
        changeSelection(curSelected + huh);
    }

    function changeSelection(newSelection:Int) {
        if (newSelection != curSelected) {
            FlxG.sound.play(Paths.sound('scrollMenu'));
        }
        
        curSelected = newSelection;
        if (curSelected >= menuItems.length) curSelected = 0;
        if (curSelected < 0) curSelected = menuItems.length - 1;
        
        menuBoxes.forEach(function(box:FlxSprite) {
            box.alpha = (box.ID == curSelected ? 0.2 : 0); 
        });

        menuItems.forEach(function(txt:FlxText) {
            txt.color = (txt.ID == curSelected ? FlxColor.YELLOW : FlxColor.WHITE); 
            
            if (txt.ID == curSelected) {
                txt.scale.set(1.22, 0.78);
                FlxTween.tween(txt.scale, {x: 1.08, y: 1.08}, 0.35, {ease: FlxEase.elasticOut});
            } else {
                FlxTween.tween(txt.scale, {x: 1.0, y: 1.0}, 0.15);
            }
        });
    }

    function selectItem() {
        selectedSomethin = true;
        FlxG.sound.play(Paths.sound('confirmMenu'));
        if (typeTimer != null) typeTimer.cancel(); 
        if (autoNextTimer != null) autoNextTimer.cancel();

        menuItems.forEach(function(spr:FlxText) {
            if (curSelected == spr.ID) {
                FlxFlicker.flicker(spr, 1, 0.06, false, false, function(flick:FlxFlicker) {
                    if (!isOriSleeping) {
                        playFarewellDialogue();
                    } else {
                        var shiftDistance:Float = 600;
                        FlxTween.tween(uiPanel, {x: uiPanel.x + shiftDistance, alpha: 0}, 0.3, {ease: FlxEase.backIn});
                        FlxTween.tween(logo, {x: logo.x + shiftDistance, alpha: 0}, 0.3, {ease: FlxEase.backIn});
                        
                        FlxTween.tween(songProgressBarBG, {alpha: 0}, 0.3, {ease: FlxEase.backIn});
                        FlxTween.tween(songProgressBar, {alpha: 0}, 0.3, {ease: FlxEase.backIn});
                        FlxTween.tween(nowPlayingText, {alpha: 0}, 0.3, {ease: FlxEase.backIn});
                        FlxTween.tween(songTimeText, {alpha: 0}, 0.3, {ease: FlxEase.backIn});
                        FlxTween.tween(stopButton, {alpha: 0}, 0.3, {ease: FlxEase.backIn});

                        menuBoxes.forEach(function(b) { FlxTween.tween(b, {x: b.x + shiftDistance}, 0.3, {ease: FlxEase.backIn}); });
                        menuItems.forEach(function(t) { FlxTween.tween(t, {x: t.x + shiftDistance}, 0.3, {ease: FlxEase.backIn}); });
                        
                        new FlxTimer().start(0.35, function(t) {
                            executeStateChange();
                        });
                    }
                });
            } else {
                 FlxTween.tween(spr, {alpha: 0}, 0.4);
                 menuBoxes.forEach(function(box:FlxSprite) { if(box.ID != curSelected) FlxTween.tween(box, {alpha: 0}, 0.4); });
            }
        });
    }

    function executeStateChange() {
        var choice:String = optionShit[curSelected];
        isLeavingState = false; 
        
        if (musicVolumeTween != null) musicVolumeTween.cancel();
        currentVolumeMultiplier = 1.0;
        if (FlxG.sound.music != null) {
            FlxG.sound.music.volume = originalMusicVolume;
        }
        isOriSleeping = false;
        switch (choice) {
            case 'story_mode': 
                MusicBeatState.switchState(new StoryMenuState());
            case 'freeplay': 
                host.openSubState(new FreeplayState());
                host.subStateClosed.addOnce(function(s){ reshowMenu(); });
            case 'credits': 
                MusicBeatState.switchState(new CreditsState());
            case 'options': 
                host.goToOptions();
        }
    }

    function reshowMenu() {
        selectedSomethin = false;
        isLeavingState = false;
        isDialogueActive = false;
        isDialogueTweening = false;
        isSecretDialogueActive = false;

        var boxWidth:Int = 400;
        var targetX = (FlxG.width - (panelWidth / 2)) - (boxWidth / 2) - 50;
        uiPanel.x = FlxG.width - panelWidth - 50;
        logo.x = 730;
        menuItems.forEach(function(spr:FlxText) { 
            spr.x = targetX;
            spr.alpha = 1; 
            spr.visible = true; 
        });
        menuBoxes.forEach(function(box:FlxSprite) { 
            box.x = targetX;
            box.alpha = (box.ID == curSelected ? 0.2 : 0);
            box.visible = true; 
        });
        logo.alpha = 1;
        uiPanel.alpha = 0.3;
        versionTexts.forEach(function(txt:FlxText) { txt.alpha = 1; });

        songProgressBarBG.alpha = 0.4;
        songProgressBar.alpha = 1;
        nowPlayingText.alpha = 0.8;
        songTimeText.alpha = 0.8;
        
        if (canStopMusic) {
            stopButton.text = "[STOP]";
            stopButton.color = FlxColor.RED;
        }
        stopButton.alpha = 1;
        
        FlxG.mouse.visible = true; 
        isMouseSeized = false;

        if (isOriSleeping) {
            currentVolumeMultiplier = 0.20;
            playYunaAnim('idlesleep', true);
        } else {
            wakeOriUp();
        }
    }

    function startOriDeath() {
        oriDead = true;
        selectedSomethin = true;
        var fallTime:Float = 2.5;
        var fallEase = FlxEase.quadIn; 
        var dropDist:Float = FlxG.height + 1000;
        FlxTween.tween(yunaChar, {y: dropDist, angle: 120}, fallTime, {ease: fallEase});
        FlxTween.tween(uiPanel, {y: dropDist}, fallTime, {ease: fallEase});
        FlxTween.tween(logo, {y: dropDist, angle: -25}, fallTime, {ease: fallEase});
        FlxTween.tween(hintText, {y: dropDist}, fallTime, {ease: fallEase});

        FlxTween.tween(songProgressBarBG, {y: dropDist}, fallTime, {ease: fallEase});
        FlxTween.tween(songProgressBar, {y: dropDist}, fallTime, {ease: fallEase});
        FlxTween.tween(nowPlayingText, {y: dropDist}, fallTime, {ease: fallEase});
        FlxTween.tween(songTimeText, {y: dropDist}, fallTime, {ease: fallEase});
        FlxTween.tween(stopButton, {y: dropDist}, fallTime, {ease: fallEase});

        menuBoxes.forEach(function(box:FlxSprite) { FlxTween.tween(box, {y: dropDist, angle: FlxG.random.float(-20, 20)}, fallTime, {ease: fallEase}); });
        menuItems.forEach(function(txt:FlxText) { FlxTween.tween(txt, {y: dropDist}, fallTime, {ease: fallEase}); });
        versionTexts.forEach(function(vTxt:FlxText) { FlxTween.tween(vTxt, {y: dropDist}, fallTime, {ease: fallEase}); });
        FlxTween.tween(dialogueBox, {y: dropDist}, fallTime, {ease: fallEase});
        FlxTween.tween(nameText, {y: dropDist}, fallTime, {ease: fallEase});
        
        if(FlxG.sound.music != null) {
            FlxG.sound.music.fadeOut(fallTime, 0, function(twn:FlxTween) {
                FlxG.sound.music.stop();
            });
        }

        new FlxTimer().start(fallTime + 0.5, function(tmr:FlxTimer) {
            FlxG.camera.fade(FlxColor.BLACK, 1.5, false, function() {
                new FlxTimer().start(2.0, function(tmrExit:FlxTimer) {
                    Application.current.window.alert("oof I'm Kicking your butt!", "Yasa");
                    #if sys Sys.exit(0); #else openfl.system.System.exit(0); #end
               });
            });
        });
    }
}