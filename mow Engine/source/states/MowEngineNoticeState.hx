package states;

import flixel.FlxG;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;

/**
 * Mow Engine's local version/identity page.
 * Intentionally does not query or compare against P-Slice release versions.
 */
class MowEngineNoticeState extends MusicBeatState
{
	var nextState:FlxState;

	public function new(nextState:FlxState)
	{
		super();
		this.nextState = nextState;
	}

	override public function create():Void
	{
		super.create();
		FlxG.mouse.visible = false;
		bgColor = FlxColor.BLACK;

		var title = new FlxText(36, FlxG.height * 0.12, FlxG.width - 72, "Mow Engine", 42);
		title.setFormat(null, 42, FlxColor.WHITE, "center");
		add(title);

		var version:String = MainMenuState.MowVersion;
		var versionIsBlank:Bool = version == null || version.length == 0;
		if (!versionIsBlank)
		{
			versionIsBlank = true;
			for (i in 0...version.length)
			{
				var charCode = version.charCodeAt(i);
				if (charCode != 32 && charCode != 9 && charCode != 10 && charCode != 13)
				{
					versionIsBlank = false;
					break;
				}
			}
		}
		if (versionIsBlank)
			version = "Custom Build";

		var bodyText:String = "Mow Engine detected\n" +
			"Version " + version + "\n\n" +
			"You're running a custom Mow Engine build.\n" +
			"This build uses its own version identity, not the upstream P-Slice version.\n\n" +
			"Press ESCAPE to continue.\n\n" +
			"Thanks for using Mow Engine!";

		var body = new FlxText(42, FlxG.height * 0.29, FlxG.width - 84, bodyText, 25);
		body.setFormat(null, 25, FlxColor.WHITE, "center");
		add(body);
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.ENTER || FlxG.mouse.justPressed)
			MusicBeatState.switchState(nextState);
	}
}
