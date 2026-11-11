package states.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import haxe.Json;
import backend.Song;
import states.editors.content.*;
#if sys
import sys.io.File;
#end
import lime.app.Application;
#if sys
import lime.ui.Window;
#end

/**
 * Shared UI and conversion pipeline for the standalone chart converter.
 * The target-specific wrapper states choose the actual output format.
 *
 * Known formats are detected by structure. Unknown engines are accepted only
 * when their JSON exposes recognizable note/time/lane fields; uncertain or
 * unsupported values are reported instead of silently discarded.
 */
class ChartConverterState extends MusicBeatState
{
	public var targetVersion:String = '1.0.4';

	var fileDialog:FileDialogHandler = new FileDialogHandler();
	var titleText:FlxText;
	var sourceText:FlxText;
	var statusText:FlxText;
	var reportText:FlxText;
	var reportScrollText:FlxText;
	var reportFrame:FlxSprite;
	var reportLines:Array<String> = [];
	var reportScroll:Int = 0;
	var target104Button:PsychUIButton;
	var target063Button:PsychUIButton;
	var dropFrame:FlxSprite;
	var dropHintText:FlxText;
	var previewFrame:FlxSprite;
	var previewSprites:Array<FlxSprite> = [];
	var sourcePath:String = '';
	var sourceFormat:String = 'Not loaded';
	var sourceRoot:Dynamic;
	var sourceMetadata:Dynamic;
	var pendingVSliceRoot:Dynamic;
	var pendingVSlicePath:String = '';
	var normalized:Dynamic;
	var outputData:Dynamic;
	var outputJson:String = '';
	var outputName:String = 'converted-chart.json';
	var conversionWarnings:Array<String> = [];
	var droppedNotes:Int = 0;
	var droppedEvents:Int = 0;
	var timeMultiplier:Float = 1.0;
	#if sys
	var dropWindow:Window;
	var dropHandler:String->Void;
	var dropListenerAttached:Bool = false;
	var pendingDropPaths:Array<String> = [];
	var dropBatchTimer:FlxTimer;
	#end
	var leaving:Bool = false;

	static inline var PREVIEW_X:Float = 36;
	static inline var PREVIEW_Y:Float = 382;
	static inline var PREVIEW_W:Float = 1208;
	static inline var PREVIEW_H:Float = 270;
	static inline var REPORT_X:Float = 36;
	static inline var REPORT_Y:Float = 249;
	static inline var REPORT_W:Float = 1208;
	static inline var REPORT_H:Float = 119;
	static inline var REPORT_VISIBLE_LINES:Int = 5;

	public function new(targetVersion:String = '1.0.4')
	{
		super();
		this.targetVersion = targetVersion == '0.6.3' ? '0.6.3' : '1.0.4';
	}

	override function create():Void
	{
		FlxG.camera.bgColor = 0xFF10141B;
		FlxG.mouse.visible = true;
		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Universal Chart Converter', null);
		#end

		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF10141B);
		add(bg);

		titleText = new FlxText(36, 16, FlxG.width - 72, 'UNIVERSAL CHART CONVERTER', 27);
		titleText.color = FlxColor.WHITE;
		add(titleText);

		var subtitle = new FlxText(38, 52, FlxG.width - 76,
			'Auto Detect  •  BPM / Timing  •  Note Mapping  •  Events  •  Scrollable Report  •  Preview before Save', 14);
		subtitle.color = 0xFFB8C4D3;
		add(subtitle);

		addButton(36, 82, 'Open Chart JSON...', chooseChart, 174);
		target104Button = addButton(218, 82, 'Output: Psych 1.0.4', function() selectTarget('1.0.4'), 175);
		target063Button = addButton(401, 82, 'Output: Psych 0.6.3', function() selectTarget('0.6.3'), 175);
		addButton(584, 82, 'Preview / Convert', convertCurrent, 165);
		addButton(757, 82, 'Save Converted Chart', saveConverted, 185);
		addButton(950, 82, 'Clear', clearChart, 100);
		addButton(1058, 82, 'Back', goBack, 100);
		updateTargetButtons();

		sourceText = new FlxText(38, 127, FlxG.width - 76, 'Source: no file selected', 14);
		sourceText.color = 0xFFE6EDF5;
		add(sourceText);

		statusText = new FlxText(38, 151, FlxG.width - 76,
			'Ready. Drop a .json Chart into the highlighted area below, or use Open Chart JSON.', 13);
		statusText.color = 0xFF77D6A3;
		add(statusText);

		dropFrame = new FlxSprite(36, 178).makeGraphic(1208, 37, 0xFF1B2A3B);
		add(dropFrame);
		dropHintText = new FlxText(48, 187, 1184,
			'DROP CHART JSON HERE  |  ลากไฟล์ .json จาก Explorer มาวางตรงนี้ได้  |  หรือกด Open Chart JSON...', 14);
		dropHintText.color = 0xFF9CCBFF;
		add(dropHintText);

		var reportHeader = new FlxText(38, 224, 500, 'CONVERSION REPORT', 17);
		reportHeader.color = 0xFF83B9FF;
		add(reportHeader);
		reportFrame = new FlxSprite(REPORT_X, REPORT_Y).makeGraphic(Std.int(REPORT_W), Std.int(REPORT_H), 0xFF171E28);
		add(reportFrame);
		reportText = new FlxText(REPORT_X + 10, REPORT_Y + 7, REPORT_W - 20, 'Waiting for input.', 13);
		reportText.color = 0xFFD2D9E2;
		reportText.setFormat(null, 13, FlxColor.WHITE, LEFT);
		add(reportText);
		reportScrollText = new FlxText(REPORT_X + 10, REPORT_Y + REPORT_H - 18, REPORT_W - 20, 'Mouse wheel / Up / Down to scroll report', 10);
		reportScrollText.color = 0xFF8B9CB1;
		add(reportScrollText);

		previewFrame = new FlxSprite(PREVIEW_X, PREVIEW_Y).makeGraphic(Std.int(PREVIEW_W), Std.int(PREVIEW_H), 0xFF171E28);
		add(previewFrame);
		var previewTitle = new FlxText(PREVIEW_X + 12, PREVIEW_Y + 8, PREVIEW_W - 24,
			'CHART PREVIEW  —  notes are positioned by time; rows represent lanes 0–7', 14);
		previewTitle.color = 0xFFB8C4D3;
		add(previewTitle);

		drawEmptyGrid();
		super.create();
		attachDropListener();	
		#if sys
		if (dropListenerAttached)
			setStatus('Ready — drag a .json Chart from Explorer and drop it onto the highlighted drop area.');
		else
			setStatus('Native drag-and-drop could not be attached on this build. Use Open Chart JSON.', true);
		#else
		setStatus('Native OS drag-and-drop is available on desktop builds only. Use Open Chart JSON.');
		#end
	}

	function addButton(x:Float, y:Float, label:String, callback:Void->Void, width:Int):PsychUIButton
	{
		var button:PsychUIButton = new PsychUIButton(x, y, label, callback, width);
		button.normalStyle.bgColor = 0xFF33445A;
		button.normalStyle.textColor = FlxColor.WHITE;
		add(button);
		return button;
	}

	function selectTarget(target:String):Void
	{
		targetVersion = target == '0.6.3' ? '0.6.3' : '1.0.4';
		updateTargetButtons();
		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Universal Chart Converter - Psych $targetVersion', null);
		#end
		if (normalized != null) convertCurrent();
		else setStatus('Output target selected: Psych $targetVersion. Load a Chart to continue.');
	}

	function updateTargetButtons():Void
	{
		if (target104Button != null)
			target104Button.normalStyle.bgColor = targetVersion == '1.0.4' ? 0xFF287A54 : 0xFF33445A;
		if (target063Button != null)
			target063Button.normalStyle.bgColor = targetVersion == '0.6.3' ? 0xFF287A54 : 0xFF33445A;
	}

	function chooseChart():Void
	{
		if (!fileDialog.completed) return;
		fileDialog.open('chart.json', 'Open an Engine Chart JSON', function()
		{
			loadInputText(fileDialog.data, fileDialog.path);
		});
	}

	function loadPath(path:String):Void
	{
		#if sys
		try
		{
			if (path == null || !path.toLowerCase().endsWith('.json'))
			{
				setStatus('Only JSON Chart / V-Slice metadata files are supported by this importer.', true);
				return;
			}
			loadInputText(File.getContent(path), path);
		}
		catch (e:Dynamic)
		{
			setStatus('Could not read dropped file: ' + Std.string(e), true);
		}
		#else
		setStatus('File dropping is available on desktop/sys builds. Use Open Chart on this target.', true);
		#end
	}

	/** A V-Slice chart and metadata are a pair. When the OS reports multiple dropped paths,
		collect them briefly before importing so the metadata file is available regardless of drop order. */
	function processDropBatch(paths:Array<String>):Void
	{
		#if sys
		if (paths == null || paths.length == 0) return;
		var vsliceChartPath:String = '';
		var vsliceMetadataPath:String = '';
		for (path in paths)
		{
			if (path == null || !path.toLowerCase().endsWith('.json') || !FileSystem.exists(path)) continue;
			try
			{
				var parsed:Dynamic = Json.parse(File.getContent(path));
				if (isVSliceMetadata(parsed, path)) vsliceMetadataPath = path;
				else if (detectFormat(parsed) == 'V-Slice') vsliceChartPath = path;
			}
			catch (_:Dynamic) {}
		}
		if (vsliceChartPath != '')
		{
			var metaPath = vsliceMetadataPath != '' ? vsliceMetadataPath : findMatchingVSliceMetadata(vsliceChartPath);
			if (metaPath != '')
			{
				loadVSlicePair(vsliceChartPath, metaPath);
				return;
			}
			loadPath(vsliceChartPath); // Falls back to the manual picker only if no matching metadata is available.
			return;
		}
		if (vsliceMetadataPath != '')
		{
			var chartPath = findVSliceChartForMetadata(vsliceMetadataPath);
			if (chartPath != '')
			{
				loadVSlicePair(chartPath, vsliceMetadataPath);
				return;
			}
			setStatus('V-Slice metadata detected, but no matching chart.json was found. Drag chart.json and metadata.json together, or drop the chart file.', true);
			return;
		}
		// For ordinary files, load the last dropped file (the usual OS order is chart first).
		loadPath(paths[paths.length - 1]);
		#else
		if (paths != null && paths.length > 0) loadPath(paths[paths.length - 1]);
		#end
	}

	function loadInputText(text:String, path:String):Void
	{
		try
		{
			if (text == null || text.length == 0) throw 'The selected file is empty.';
			var root:Dynamic = Json.parse(text);
			if (root == null) throw 'The selected file does not contain a JSON object.';
			if (isVSliceMetadata(root, path))
			{
				#if sys
				var chartPath = findVSliceChartForMetadata(path);
				if (chartPath != '')
				{
					loadVSlicePair(chartPath, path);
					return;
				}
				setStatus('V-Slice metadata detected. Drop it together with the matching chart.json, or place both files in the same song folder.', true);
				return;
				#else
				setStatus('V-Slice metadata detected. Select the matching chart.json on this target.', true);
				return;
				#end
			}
			sourcePath = path == null ? '' : path;
			sourceFormat = detectFormat(root);
			if (sourceText != null) sourceText.text = 'Source: ' + (sourcePath == '' ? '(dropped / unnamed file)' : sourcePath) + '  |  detected: ' + sourceFormat;
			sourceRoot = root;
			sourceMetadata = null;
			if (sourceFormat == 'V-Slice')
			{
				pendingVSliceRoot = root;
				pendingVSlicePath = sourcePath;
				#if sys
				var metadataPath = findMatchingVSliceMetadata(sourcePath);
				if (metadataPath != '')
				{
					loadVSlicePair(sourcePath, metadataPath);
					return;
				}
				#end
				setStatus('V-Slice detected, but matching metadata.json was not found near this chart. Select it manually or drop both files together.');
				if (!fileDialog.completed) return;
				fileDialog.open('metadata.json', 'Select matching V-Slice metadata.json', function()
				{
					try
					{
						loadVSlicePair(pendingVSlicePath, fileDialog.path);
					}
					catch (e:Dynamic)
					{
						setStatus('Could not read V-Slice metadata: ' + Std.string(e), true);
					}
				});
				return;
			}
			prepareConversion();
		}
		catch (e:Dynamic)
		{
			setStatus('Invalid Chart JSON: ' + Std.string(e), true);
		}
	}

	function loadVSlicePair(chartPath:String, metadataPath:String):Void
	{
		#if sys
		try
		{
			if (chartPath == null || metadataPath == null || !FileSystem.exists(chartPath) || !FileSystem.exists(metadataPath))
				throw 'Both chart.json and metadata.json must be available.';
			var chartRoot:Dynamic = Json.parse(File.getContent(chartPath));
			var metadataRoot:Dynamic = Json.parse(File.getContent(metadataPath));
			if (detectFormat(chartRoot) != 'V-Slice') throw 'The selected chart file is not a recognized V-Slice chart.';
			if (!isVSliceMetadata(metadataRoot, metadataPath)) throw 'The selected metadata file does not look like V-Slice metadata.json.';
			sourceRoot = chartRoot;
			sourceMetadata = metadataRoot;
			sourcePath = chartPath;
			sourceFormat = 'V-Slice';
			pendingVSliceRoot = chartRoot;
			pendingVSlicePath = chartPath;
			if (sourceText != null) sourceText.text = 'Source: ' + chartPath + ' + ' + metadataPath + '  |  detected: V-Slice (Chart + Metadata)';
			setStatus('V-Slice chart and metadata loaded together. BPM changes and difficulty metadata are available.');
			prepareConversion();
		}
		catch (e:Dynamic)
		{
			setStatus('Could not load V-Slice chart/metadata pair: ' + Std.string(e), true);
		}
		#else
		setStatus('Loading a V-Slice file pair requires a desktop/sys build. Use the manual import flow.', true);
		#end
	}

	function isVSliceMetadata(root:Dynamic, path:String):Bool
	{
		var lowerPath = path == null ? '' : path.replace('\\', '/').toLowerCase();
		var base = lowerPath;
		var slash = base.lastIndexOf('/');
		if (slash >= 0) base = base.substr(slash + 1);
		if (base == 'metadata.json') return true;
		return root != null && hasField(root, 'songName') && hasField(root, 'playData') && hasField(root, 'timeChanges') && !hasField(root, 'scrollSpeed');
	}

	#if sys
	function normalizeFsPath(path:String):String
	{
		return path == null ? '' : path.replace('\\', '/');
	}

	function pathDirectory(path:String):String
	{
		var p = normalizeFsPath(path);
		var slash = p.lastIndexOf('/');
		return slash <= 0 ? '.' : p.substr(0, slash);
	}

	function joinFsPath(dir:String, name:String):String
	{
		var d = normalizeFsPath(dir);
		if (d == '' || d == '.') return name;
		if (d.endsWith('/')) return d + name;
		return d + '/' + name;
	}

	function findMatchingVSliceMetadata(chartPath:String):String
	{
		var dir = pathDirectory(chartPath);
		var candidates:Array<String> = [joinFsPath(dir, 'metadata.json')];
		// Some packs put charts in a /charts subfolder and keep metadata one level above it.
		var last = dir.substr(dir.lastIndexOf('/') + 1).toLowerCase();
		if (last == 'charts') candidates.push(joinFsPath(pathDirectory(dir), 'metadata.json'));
		var parent = pathDirectory(dir);
		if (parent != dir && parent != '.') candidates.push(joinFsPath(parent, 'metadata.json'));
		for (candidate in candidates)
			if (FileSystem.exists(candidate) && !FileSystem.isDirectory(candidate)) return candidate;
		return '';
	}

	function findVSliceChartForMetadata(metadataPath:String):String
	{
		var dir = pathDirectory(metadataPath);
		var canonical = joinFsPath(dir, 'chart.json');
		if (FileSystem.exists(canonical) && !FileSystem.isDirectory(canonical))
		{
			try { if (detectFormat(Json.parse(File.getContent(canonical))) == 'V-Slice') return canonical; } catch (_:Dynamic) {}
		}
		var candidateDirs:Array<String> = [dir, joinFsPath(dir, 'charts')];
		for (candidateDir in candidateDirs)
		{
			if (!FileSystem.exists(candidateDir) || !FileSystem.isDirectory(candidateDir)) continue;
			for (file in FileSystem.readDirectory(candidateDir))
			{
				if (file.toLowerCase() == 'metadata.json' || !file.toLowerCase().endsWith('.json')) continue;
				var candidate = joinFsPath(candidateDir, file);
				try { if (detectFormat(Json.parse(File.getContent(candidate))) == 'V-Slice') return candidate; } catch (_:Dynamic) {}
			}
		}
		return '';
	}
	#end

	function prepareConversion():Void
	{
		conversionWarnings = [];
		droppedNotes = 0;
		droppedEvents = 0;
		try
		{
			normalized = normalizeChart(sourceRoot, sourceMetadata, sourceFormat);
			if (normalized == null) throw 'Could not recognize a note array in this JSON.';
			convertCurrent();
		}
		catch (e:Dynamic)
		{
			outputData = null;
			outputJson = '';
			setStatus('Import failed: ' + Std.string(e), true);
		}
	}

	function convertCurrent():Void
	{
		if (normalized == null)
		{
			setStatus('Load a Chart first.', true);
			return;
		}
		try
		{
			conversionWarnings = cast normalized.warnings;
			var legacySong:Dynamic = buildLegacySong(normalized);
			if (targetVersion == '1.0.4')
			{
				// Use the engine's real migration function instead of only changing the format label.
				Reflect.setField(legacySong, 'format', 'psych_v1_convert');
				Song.convert(cast legacySong);
				outputData = legacySong;
				outputName = safeSongName(Std.string(normalized.song)) + '-psych104.json';
			}
			else
			{
				// Psych 0.6.3 reads the legacy { song: { ... } } wrapper.
				outputData = {song: legacySong};
				outputName = safeSongName(Std.string(normalized.song)) + '-psych063.json';
			}
			outputJson = PsychJsonPrinter.print(outputData, ['sectionNotes', 'events']);
			if (outputJson == null || outputJson.length == 0) throw 'Exporter produced an empty JSON result.';
			updateReport();
			renderPreview();
			setStatus('Conversion preview ready. Review the report and chart preview before saving.');
		}
		catch (e:Dynamic)
		{
			outputData = null;
			outputJson = '';
			clearPreviewNotes();
			updateReport('Conversion failed: ' + Std.string(e));
			setStatus('Conversion failed: ' + Std.string(e), true);
		}
	}

	function saveConverted():Void
	{
		if (outputJson == null || outputJson.length == 0 || outputData == null)
		{
			setStatus('Nothing to save. Load a Chart and preview the conversion first.', true);
			return;
		}
		if (!fileDialog.completed) return;
		fileDialog.save(outputName, outputJson, function()
		{
			setStatus('Saved converted Chart: ' + fileDialog.path);
		}, null, function()
		{
			setStatus('Could not save the converted Chart.', true);
		});
	}

	function clearChart():Void
	{
		sourcePath = '';
		sourceFormat = 'Not loaded';
		leaving = false;
		droppedNotes = 0;
		droppedEvents = 0;
		timeMultiplier = 1.0;
		sourceRoot = null;
		sourceMetadata = null;
		normalized = null;
		outputData = null;
		outputJson = '';
		conversionWarnings = [];
		sourceText.text = 'Source: no file selected';
		reportLines = ['Waiting for input.'];
		reportScroll = 0;
		renderReportPage();
		setStatus('Ready — drop a .json Chart into the highlighted area or use Open Chart JSON.');
		clearPreviewNotes();
		drawEmptyGrid();
	}

	function goBack():Void
	{
		if (leaving) return;
		leaving = true;
		MusicBeatState.switchState(new MasterEditorMenu());
	}

	function detectFormat(root:Dynamic):String
	{
		if (root == null) return 'Unknown JSON';
		// Codename Engine stores notes under strumLines, not root.notes/notes[].sectionNotes.
		// Its native Chart.hx marks files with codenameChart=true and includes meta + scrollSpeed.
		var codeLines:Dynamic = getField(root, 'strumLines');
		if (getBool(root, ['codenameChart'], false) ||
			(Std.isOfType(codeLines, Array) && hasField(root, 'meta') && hasField(root, 'scrollSpeed')))
			return 'Codename Engine';
		var fmt = getString(root, ['format'], '');
		var chart = getField(root, 'song');
		if (fmt.toLowerCase().startsWith('psych_v1')) return 'Psych Engine 1.x (' + fmt + ')';
		if (hasField(root, 'version') && hasField(root, 'scrollSpeed') && hasField(root, 'notes')) return 'V-Slice';
		if (chart != null && !Std.isOfType(chart, String) && hasField(chart, 'notes')) return 'Psych / Kade / Legacy wrapped Chart';
		if (hasField(root, 'notes') && Std.isOfType(getField(root, 'notes'), Array))
		{
			var rows:Array<Dynamic> = cast getField(root, 'notes');
			if (rows.length > 0 && hasField(rows[0], 'sectionNotes')) return 'Psych / Legacy sectional Chart';
			if (rows.length > 0 && (hasField(rows[0], 'time') || hasField(rows[0], 'strumTime') || hasField(rows[0], 't'))) return 'Generic flat-note Chart';
			return 'Psych-compatible / Generic JSON Chart';
		}
		if (hasField(root, 'notes')) return 'Generic JSON Chart (heuristic)';
		return 'Unknown / unsupported Chart JSON';
	}

	function normalizeChart(root:Dynamic, metadata:Dynamic, detected:String):Dynamic
	{
		var chart:Dynamic = root;
		var wrappedSong = getField(root, 'song');
		if (wrappedSong != null && !Std.isOfType(wrappedSong, String) && hasField(wrappedSong, 'notes')) chart = wrappedSong;

		var codenameMeta:Dynamic = getField(chart, 'meta');
		var name = getString(chart, ['song', 'songName', 'name'],
			getString(codenameMeta, ['name', 'songName', 'song'], metadata != null ? getString(metadata, ['songName', 'song'], 'Converted Song') : 'Converted Song'));
		var unit:String = getString(chart, ['timeUnit', 'timeUnits', 'timestampUnit'], 'ms').toLowerCase();
		timeMultiplier = (unit == 's' || unit == 'sec' || unit == 'second' || unit == 'seconds') ? 1000.0 : ((unit == 'us' || unit == 'microseconds') ? 0.001 : 1.0);
		if (detected == 'V-Slice' || detected == 'Codename Engine') timeMultiplier = 1.0;
		var bpm = getFloat(chart, ['bpm', 'BPM'], getFloat(codenameMeta, ['bpm', 'BPM'], 100));
		var speed = getFloat(chart, ['speed', 'scrollSpeed'], 1);
		var needsVoices = getBool(chart, ['needsVoices', 'voices'], getBool(codenameMeta, ['needsVoices'], true));
		var player1 = getString(chart, ['player1', 'player'], 'bf');
		var player2 = getString(chart, ['player2', 'opponent'], 'dad');
		var gfVersion = getString(chart, ['gfVersion', 'girlfriend'], 'gf');
		if (detected == 'Codename Engine')
		{
			var codeLinesForChars:Dynamic = getField(chart, 'strumLines');
			if (Std.isOfType(codeLinesForChars, Array))
			{
				var characterLines:Array<Dynamic> = cast codeLinesForChars;
				for (lineIndex in 0...characterLines.length)
				{
					var line:Dynamic = characterLines[lineIndex];
					var role:String = codenameLineRole(line, lineIndex, characterLines.length);
					var character:String = codenameLineCharacter(line);
					if (character == '' || character.toLowerCase() == 'none') continue;
					switch (role)
					{
						case 'player': player1 = character;
						case 'opponent': player2 = character;
						case 'gf': gfVersion = character;
						case 'additional': conversionWarnings.push('Codename strum line ' + (lineIndex + 1) + ' character "' + character + '" is treated as an additional Dad-side note line; its separate character cannot be represented by a standard Psych chart.');
					}
				}
			}
		}
		var stage = getString(chart, ['stage'], 'stage');
		var offset = getFloat(chart, ['offset'], 0);
		if (metadata != null)
		{
			var timeChanges = getField(metadata, 'timeChanges');
			if (Std.isOfType(timeChanges, Array))
			{
				var changes:Array<Dynamic> = cast timeChanges;
				if (changes.length > 0) bpm = getFloat(changes[0], ['bpm', 'b'], bpm);
			}
			var chars = getField(getField(metadata, 'playData'), 'characters');
			if (Std.isOfType(chars, Array))
			{
				var ca:Array<Dynamic> = cast chars;
				if (ca.length > 0) player1 = Std.string(ca[0]);
				if (ca.length > 1) player2 = Std.string(ca[1]);
				if (ca.length > 2) gfVersion = Std.string(ca[2]);
			}
			else if (chars != null)
			{
				player1 = getString(chars, ['player', 'bf'], player1);
				player2 = getString(chars, ['opponent', 'dad'], player2);
				gfVersion = getString(chars, ['girlfriend', 'gf'], gfVersion);
			}
		}

		var rawNotes:Dynamic = getField(chart, 'notes');
		var vSliceDiff:String = '';
		var noteRows:Array<Dynamic> = [];
		var sourceSections:Array<Dynamic> = [];
		var isLegacySectionChart:Bool = false;

		if (detected == 'Codename Engine')
		{
			// Codename stores notes under strumLines[].notes; time and sLen are milliseconds.
			// Resolve BF/Dad from line metadata when present, treat line 3 as GF, and lines 4+ as special Dad-side notes.
			var codeLines:Dynamic = getField(chart, 'strumLines');
			if (!Std.isOfType(codeLines, Array)) throw 'Codename Engine chart is missing its strumLines array.';
			var lineArray:Array<Dynamic> = cast codeLines;
			var noteTypes:Dynamic = getField(chart, 'noteTypes');
			var warnedAdditional:Bool = false;
			var warnedGF:Bool = false;
			for (lineIndex in 0...lineArray.length)
			{
				var line:Dynamic = lineArray[lineIndex];
				var role:String = codenameLineRole(line, lineIndex, lineArray.length);
				var keyCount:Int = Std.int(safeNumber(getField(line, 'keyCount'), 4));
				if (keyCount != 4)
					conversionWarnings.push('Codename strum line ' + (lineIndex + 1) + ' uses ' + keyCount + ' keys. Lanes are mapped modulo 4 for Psych; verify manually.');
				var lineNotes:Dynamic = getField(line, 'notes');
				if (!Std.isOfType(lineNotes, Array)) continue;
				if (role == 'additional' && !warnedAdditional)
				{
					conversionWarnings.push('Codename strum lines 4+ are mapped to Dad-side lanes 4–7. Existing note types are preserved; blank types are marked as Codename Additional Line N because Psych cannot reproduce a separate strumline directly.');
					warnedAdditional = true;
				}
				if (role == 'gf' && !warnedGF)
				{
					conversionWarnings.push('Codename strum line 3 is mapped to GF using the "GF Sing" note type on the Dad-side lane. The target game must support GF Sing note types for the GF animation to play.');
					warnedGF = true;
				}
				for (rawNote in (cast lineNotes : Array<Dynamic>))
				{
					if (rawNote == null || !hasField(rawNote, 'time') || !hasField(rawNote, 'id')) { droppedNotes++; continue; }
					var t:Float = safeNumber(getField(rawNote, 'time'), -1);
					var id:Int = Std.int(safeNumber(getField(rawNote, 'id'), 0));
					if (t < 0 || id < 0) { droppedNotes++; conversionWarnings.push('Codename note had an invalid negative time or lane and was skipped.'); continue; }
					var lane:Int = id % 4;
					if (role != 'player') lane += 4; // Dad, GF and extra lines use Dad-side output lanes.
					var length:Float = Math.max(0, safeNumber(getField(rawNote, 'sLen'), safeNumber(getField(rawNote, 'sustainLength'), 0)));
					var typeValue:Dynamic = getField(rawNote, 'type');
					var noteType:String = '';
					if (typeValue != null)
					{
						if (Std.isOfType(typeValue, Int) || Std.isOfType(typeValue, Float))
						{
							var typeIndex:Int = Std.int(safeNumber(typeValue, 0));
							if (typeIndex > 0 && Std.isOfType(noteTypes, Array) && typeIndex <= (cast noteTypes : Array<Dynamic>).length)
								noteType = Std.string((cast noteTypes : Array<Dynamic>)[typeIndex - 1]);
							else if (typeIndex > 0)
							{
								noteType = 'Codename Note Type #' + typeIndex;
								conversionWarnings.push('Codename note type index ' + typeIndex + ' was not found in noteTypes; its name was preserved as a placeholder.');
							}
						}
						else noteType = Std.string(typeValue);
					}
					if (role == 'gf')
					{
						if (noteType != '' && noteType != 'GF Sing') conversionWarnings.push('GF-line note type "' + noteType + '" was replaced with "GF Sing"; this target format supports only one note-type value per note.');
						noteType = 'GF Sing';
					}
					else if (role == 'additional' && noteType == '') noteType = 'Codename Additional Line ' + (lineIndex + 1);
					noteRows.push({time: t, lane: lane, length: length, type: noteType, sourceSection: -1, sourceStrumLine: lineIndex, sourceRole: role});
				}
			}
		}
		else
		{
			if (rawNotes != null && !Std.isOfType(rawNotes, Array))
			{
				var keys = Reflect.fields(rawNotes);
				if (keys.length > 0)
				{
					var preferred:Array<String> = ['normal', 'hard', 'easy'];
					for (diff in preferred) if (keys.contains(diff)) { vSliceDiff = diff; break; }
					if (vSliceDiff == '') vSliceDiff = keys[0];
					if (Reflect.field(rawNotes, vSliceDiff) != null && Std.isOfType(Reflect.field(rawNotes, vSliceDiff), Array))
					{
						if (keys.length > 1) conversionWarnings.push('The source contains multiple difficulties (' + keys.join(', ') + '). Preview/export currently uses only "' + vSliceDiff + '"; convert the other difficulties separately to avoid losing them.');
						rawNotes = Reflect.field(rawNotes, vSliceDiff);
						var vSliceSpeed:Dynamic = getField(chart, 'scrollSpeed');
						if (vSliceSpeed != null && !Std.isOfType(vSliceSpeed, Int) && !Std.isOfType(vSliceSpeed, Float)) speed = readNumber(vSliceSpeed, [vSliceDiff], speed);
					}
				}
			}
			if (!Std.isOfType(rawNotes, Array)) throw 'Could not locate a supported note array. This engine format needs a dedicated importer.';
			var rawSections:Array<Dynamic> = cast rawNotes;
			var sourceHasSections:Bool = rawSections.length == 0 || hasField(rawSections[0], 'sectionNotes');
			isLegacySectionChart = sourceHasSections && rawSections.length > 0;
			if (sourceHasSections)
			{
				for (sectionIndex in 0...rawSections.length)
				{
					var section = rawSections[sectionIndex];
					var meta:Dynamic = cloneJsonObject(section);
					if (hasField(meta, 'sectionNotes')) Reflect.deleteField(meta, 'sectionNotes');
					sourceSections.push(meta);
					var notesInSection:Dynamic = getField(section, 'sectionNotes');
					if (!Std.isOfType(notesInSection, Array)) continue;
					var noteArray:Array<Dynamic> = cast notesInSection;
					var mustHit:Bool = getBool(section, ['mustHitSection'], true);
					for (rawNote in noteArray)
					{
						var parsedNote = normalizeNote(rawNote, bpm, sectionIndex, true, mustHit, detected);
						if (parsedNote != null) noteRows.push(parsedNote) else droppedNotes++;
					}
				}
			}
			else
			{
				for (rawNote in rawSections)
				{
					var parsedNote = normalizeNote(rawNote, bpm, -1, false, true, detected);
					if (parsedNote != null) noteRows.push(parsedNote) else droppedNotes++;
				}
			}
		}

		var rawEvents:Dynamic = getField(chart, 'events');
		if (rawEvents == null) rawEvents = getField(root, 'events');
		var codenameChanges:Array<Dynamic> = [];
		if (detected == 'Codename Engine' && Std.isOfType(rawEvents, Array))
		{
			var eventsWithoutBpm:Array<Dynamic> = [];
			for (ev in (cast rawEvents : Array<Dynamic>))
			{
				var evName = codenameEventName(ev);
				if (evName.toLowerCase() == 'bpm change')
				{
					var params:Dynamic = getField(ev, 'params');
					var newBpm:Float = 0;
					if (Std.isOfType(params, Array) && (cast params : Array<Dynamic>).length > 0) newBpm = safeNumber((cast params : Array<Dynamic>)[0], 0);
					if (newBpm > 0) codenameChanges.push({time: safeNumber(getField(ev, 'time'), 0), bpm: newBpm});
					else conversionWarnings.push('A Codename BPM Change event had no valid BPM parameter and was skipped.');
				}
				else eventsWithoutBpm.push(ev);
			}
			rawEvents = eventsWithoutBpm;
		}
		var events = normalizeEvents(rawEvents, bpm, detected);
		var rawChanges:Dynamic = metadata != null ? getField(metadata, 'timeChanges') : getField(chart, 'timeChanges');
		if (rawChanges == null) rawChanges = getField(chart, 'bpmChanges');
		var timeChanges:Array<Dynamic> = normalizeTimeChanges(rawChanges, bpm);
		for (change in codenameChanges) timeChanges.push(change);
		timeChanges.sort(function(a:Dynamic, b:Dynamic):Int return safeNumber(getField(a, 'time'), 0) < safeNumber(getField(b, 'time'), 0) ? -1 : (safeNumber(getField(a, 'time'), 0) > safeNumber(getField(b, 'time'), 0) ? 1 : 0));
		if (detected.indexOf('Unknown') >= 0 || detected.indexOf('Generic') >= 0)
			conversionWarnings.push('Source format was inferred from common JSON fields. Please verify lanes, note type semantics and timing before using the result.');
		if (detected == 'Codename Engine')
			conversionWarnings.push('Codename note positions and sustain lengths were imported as milliseconds. Custom strum-line behavior and Codename-only events may need manual equivalents in Psych Engine.');
		if (detected == 'V-Slice' && metadata == null)
			conversionWarnings.push('V-Slice metadata was not loaded. BPM changes and character metadata may be incomplete.');
		if (noteRows.length == 0) conversionWarnings.push('No notes were found; confirm that the source difficulty contains notes.');

		var knownTypes:Map<String, Bool> = new Map();
		for (note in noteRows)
		{
			var nt:String = Std.string(getField(note, 'type'));
			if (nt != '' && nt != 'null') knownTypes.set(nt, true);
		}
		if (knownTypes.keys().hasNext())
		{
			var types:Array<String> = [];
			for (key in knownTypes.keys()) types.push(key);
			conversionWarnings.push('Non-empty note types were preserved (' + types.join(', ') + '). Target mods must provide equivalent note-type scripts/definitions.');
		}

		return {
			song: name,
			bpm: bpm,
			speed: speed,
			needsVoices: needsVoices,
			player1: player1,
			player2: player2,
			gfVersion: gfVersion,
			stage: stage,
			offset: offset,
			arrowSkin: getString(chart, ['arrowSkin'], ''),
			splashSkin: getString(chart, ['splashSkin'], ''),
			gameOverChar: getString(chart, ['gameOverChar'], 'bf'),
			gameOverSound: getString(chart, ['gameOverSound'], 'fnf_loss_sfx'),
			gameOverLoop: getString(chart, ['gameOverLoop'], 'gameOver'),
			gameOverEnd: getString(chart, ['gameOverEnd'], 'gameOverEnd'),
			disableNoteRGB: getBool(chart, ['disableNoteRGB'], false),
			notes: noteRows,
			events: events,
			sections: sourceSections,
			hasSourceSections: isLegacySectionChart,
			timeChanges: timeChanges,
			timeMultiplier: timeMultiplier,
			warnings: conversionWarnings.copy()
		};
	}

	function normalizeNote(raw:Dynamic, bpm:Float, sectionIndex:Int, fromSection:Bool, mustHitSection:Bool, detected:String):Dynamic
	{
		if (raw == null) return null;
		var time:Float = 0;
		var lane:Int = 0;
		var sustain:Float = 0;
		var noteType:String = '';
		if (Std.isOfType(raw, Array))
		{
			var tuple:Array<Dynamic> = cast raw;
			if (tuple.length < 2) return null;
			time = safeNumber(tuple[0], 0) * timeMultiplier;
			lane = Std.int(safeNumber(tuple[1], 0));
			if (tuple.length > 2) sustain = safeNumber(tuple[2], 0) * timeMultiplier;
			if (tuple.length > 3 && tuple[3] != null) noteType = Std.string(tuple[3]);
		}
		else
		{
			time = readNoteTime(raw, bpm);
			lane = Std.int(readNumber(raw, ['data', 'lane', 'noteData', 'column', 'd'], 0));
			sustain = readSustain(raw, bpm);
			noteType = getString(raw, ['type', 'noteType', 'kind', 'k'], '');
			var side:String = getString(raw, ['side', 'mustPress', 'player'], '').toLowerCase();
			if ((side == 'opponent' || side == 'dad' || side == 'false') && lane >= 0 && lane < 4) lane += 4;
			if ((side == 'player' || side == 'bf' || side == 'true') && lane >= 4 && lane < 8) lane -= 4;
		}
		if (lane < 0) lane = 0;
		if (fromSection)
		{
			// Legacy Psych lane indices are relative to mustHitSection; normalize to absolute side lanes.
			var baseLane = lane % 4;
			var isPlayer = lane < 4 ? mustHitSection : !mustHitSection;
			lane = isPlayer ? baseLane : baseLane + 4;
		}
		if (time < 0)
		{
			conversionWarnings.push('A note had negative time; it was clamped to 0 ms.');
			time = 0;
		}
		if (sustain < 0) sustain = 0;
		return {time: time, lane: lane, length: sustain, type: noteType, sourceSection: sectionIndex};
	}

	function readNoteTime(note:Dynamic, bpm:Float):Float
	{
		if (hasField(note, 'beat')) return beatsToMs(safeNumber(getField(note, 'beat'), 0), bpm);
		if (hasField(note, 'step')) return safeNumber(getField(note, 'step'), 0) * 60000 / Math.max(1, bpm * 4);
		return readNumber(note, ['time', 'strumTime', 'timestamp', 't', 'position'], 0) * timeMultiplier;
	}

	function readSustain(note:Dynamic, bpm:Float):Float
	{
		if (hasField(note, 'lengthInBeats') || hasField(note, 'sustainBeats'))
			return beatsToMs(readNumber(note, ['lengthInBeats', 'sustainBeats'], 0), bpm);
		if (hasField(note, 'lengthInSteps'))
			return readNumber(note, ['lengthInSteps'], 0) * 60000 / Math.max(1, bpm * 4);
		return readNumber(note, ['length', 'sustainLength', 'holdLength', 'duration', 'l'], 0) * timeMultiplier;
	}

	function normalizeEvents(rawEvents:Dynamic, bpm:Float, detected:String):Array<Dynamic>
	{
		var output:Array<Dynamic> = [];
		if (rawEvents == null) return output;
		if (!Std.isOfType(rawEvents, Array))
		{
			conversionWarnings.push('The source events field is not an array; events could not be converted.');
			droppedEvents++;
			return output;
		}
		var events:Array<Dynamic> = cast rawEvents;
		for (event in events)
		{
			if (event == null) { droppedEvents++; continue; }
			if (Std.isOfType(event, Array))
			{
				var row:Array<Dynamic> = cast event;
				if (row.length >= 2 && Std.isOfType(row[1], Array))
				{
					var subs:Array<Dynamic> = [];
					for (sub in (cast row[1] : Array<Dynamic>))
					{
						if (!Std.isOfType(sub, Array)) { droppedEvents++; continue; }
						var vals:Array<Dynamic> = cast sub;
						if (vals.length == 0) { droppedEvents++; continue; }
						var mappedName = mapEventName(Std.string(vals[0]));
						warnIfEventMayNotTransfer(mappedName);
						subs.push([mappedName, vals.length > 1 && vals[1] != null ? Std.string(vals[1]) : '', vals.length > 2 && vals[2] != null ? Std.string(vals[2]) : '']);
					}
					if (subs.length > 0) output.push([safeNumber(row[0], 0) * timeMultiplier, subs]);
				}
				else if (row.length >= 2)
				{
					var mappedName = mapEventName(Std.string(row[1]));
					warnIfEventMayNotTransfer(mappedName);
					output.push([safeNumber(row[0], 0) * timeMultiplier, [[mappedName, row.length > 2 ? Std.string(row[2]) : '', row.length > 3 ? Std.string(row[3]) : '']]]);
				}
				else droppedEvents++;
				continue;
			}
			var eventName = getString(event, ['name', 'event', 'eventName', 'e'], '');
			if (eventName == '' && detected == 'Codename Engine') eventName = codenameEventName(event);
			if (eventName == '')
			{
				droppedEvents++;
				conversionWarnings.push('An event entry had no recognizable event name and was skipped.');
				continue;
			}
			var at:Float = readNoteTime(event, bpm);
			var v:Dynamic = getField(event, 'values');
			if (v == null) v = getField(event, 'v');
			if (v == null) v = getField(event, 'params');
			var value1:String = '';
			var value2:String = '';
			if (Std.isOfType(v, Array))
			{
				var values:Array<Dynamic> = cast v;
				if (values.length > 0 && values[0] != null) value1 = Std.string(values[0]);
				if (values.length > 1 && values[1] != null) value2 = Std.string(values[1]);
			}
			else if (v != null)
			{
				value1 = getString(v, ['value1', 'v1', 'value'], '');
				value2 = getString(v, ['value2', 'v2'], '');
			}
			else
			{
				value1 = getString(event, ['value1', 'v1'], '');
				value2 = getString(event, ['value2', 'v2'], '');
			}
			var mappedName = mapEventName(eventName);
			warnIfEventMayNotTransfer(mappedName);
			output.push([at, [[mappedName, value1, value2]]]);
		}
		output.sort(function(a:Dynamic, b:Dynamic):Int return safeNumber(a[0], 0) < safeNumber(b[0], 0) ? -1 : (safeNumber(a[0], 0) > safeNumber(b[0], 0) ? 1 : 0));
		return output;
	}

	function warnIfEventMayNotTransfer(name:String):Void
	{
		var supportedPsych:Array<String> = [
			'Dadbattle Spotlight', 'Hey!', 'Set GF Speed', 'Philly Glow', 'Kill Henchmen', 'Add Camera Zoom',
			'BG Freaks Expression', 'Trigger BG Ghouls', 'Play Animation', 'Camera Follow Pos', 'Alt Idle Animation',
			'Screen Shake', 'Change Character', 'Change Scroll Speed', 'Set Property', 'Play Sound', 'Set Camera Bopping',
			'Zoom Camera', 'Target Camera', 'Focus Camera', 'FocusCamera', 'ZoomCamera', 'TiltCamera', 'Camera Zoom',
			'Change Stage', 'Set Camera Bop', 'Set Camera Zoom', 'Set Camera Angle'
		];
		var lower = name == null ? '' : name.toLowerCase();
		var potentiallyUnsupported = !supportedPsych.contains(name);
		if (targetVersion == '0.6.3' && (lower == 'target camera' || lower == 'focus camera' || lower == 'focuscamera' || lower == 'zoomcamera' || lower == 'tiltcamera' || lower == 'camera zoom' || lower == 'set camera angle')) potentiallyUnsupported = true;
		if (potentiallyUnsupported)
		{
			var warning = 'Event "' + name + '" was kept in the output, but the target may not implement it; provide an equivalent event script or map it manually.';
			var exists = false;
			for (old in conversionWarnings) if (old == warning) exists = true;
			if (!exists) conversionWarnings.push(warning);
		}
	}

	function mapEventName(name:String):String
	{
		var lower = name.toLowerCase().trim();
		switch (lower)
		{
			case 'dadbattle spotlight': return 'Dadbattle Spotlight';
			case 'hey!': return 'Hey!';
			case 'set gf speed', 'set girlfriend speed': return 'Set GF Speed';
			case 'philly glow': return 'Philly Glow';
			case 'kill henchmen': return 'Kill Henchmen';
			case 'add camera zoom', 'addcamerazoom': return 'Add Camera Zoom';
			case 'playsanimation', 'playanimation', 'play animation': return 'Play Animation';
			case 'camerafollowposition', 'camera follow position', 'camera follow pos': return 'Camera Follow Pos';
			case 'changescrollspeed', 'change scroll speed': return 'Change Scroll Speed';
			case 'changecharacter', 'change character': return 'Change Character';
			case 'screenshake', 'screen shake': return 'Screen Shake';
			case 'setproperty', 'set property': return 'Set Property';
			case 'alt idle animation': return 'Alt Idle Animation';
			case 'play sound': return 'Play Sound';
			case 'set camera bopping': return 'Set Camera Bopping';
			case 'bg freaks expression': return 'BG Freaks Expression';
			case 'trigger bg ghouls': return 'Trigger BG Ghouls';
			default: return name;
		}
	}

	/**
	 * Resolve Codename strumline roles.
	 * Codename ChartData.type is authoritative: 0=opponent, 1=player, 2=additional.
	 * Some charts use custom character IDs/position strings, so those must NOT override a valid type.
	 * Converter convention: line index 3 is GF; lines 4+ become extra Dad-side note types.
	 */
	function codenameLineRole(line:Dynamic, lineIndex:Int, lineCount:Int):String
	{
		// The requested converter mapping reserves the third line for GF and every later line
		// for additional Dad-side notes, regardless of the source line's generic type.
		if (lineIndex == 2) return 'gf';
		if (lineIndex >= 3) return 'additional';

		// First use Codename's actual type enum. Do this BEFORE position/character matching:
		// custom charts may have position="dad" or custom character names on the Player line.
		var rawType:Dynamic = getField(line, 'type');
		var roleNumber:Float = safeNumber(rawType, -1);
		if (roleNumber == 1) return 'player';
		if (roleNumber == 0) return 'opponent';
		if (roleNumber == 2) return 'additional';

		// Support string-based/exported variants when a converter changed the numeric enum.
		var roleText:String = rawType == null ? '' : Std.string(rawType).toLowerCase();
		if (roleText.indexOf('player') >= 0 || roleText == 'bf' || roleText.indexOf('boyfriend') >= 0) return 'player';
		if (roleText.indexOf('opponent') >= 0 || roleText == 'dad') return 'opponent';
		if (roleText.indexOf('additional') >= 0) return 'additional';

		// If the source has no usable type, inspect its placement/character metadata as a fallback.
		var position:String = getString(line, ['position'], '').toLowerCase();
		if (position.indexOf('boyfriend') >= 0 || position.indexOf('player') >= 0 || position == 'bf') return 'player';
		if (position.indexOf('girlfriend') >= 0 || position == 'gf') return 'gf';
		if (position.indexOf('opponent') >= 0 || position.indexOf('dad') >= 0) return 'opponent';

		var character:String = codenameLineCharacter(line).toLowerCase();
		if (character == 'bf' || character == 'boyfriend' || character.indexOf('bf-') == 0 || character.indexOf('boyfriend') >= 0) return 'player';
		if (character == 'gf' || character == 'girlfriend' || character.indexOf('gf-') == 0 || character.indexOf('girlfriend') >= 0) return 'gf';
		if (character == 'dad' || character == 'opponent' || character.indexOf('dad-') == 0) return 'opponent';

		// Last-resort fallback for non-standard exports missing both type and role metadata.
		// Codename's usual two-line order is opponent first, player second.
		return lineIndex == 0 ? 'opponent' : 'player';
	}

	function codenameLineCharacter(line:Dynamic):String
	{
		var chars:Dynamic = getField(line, 'characters');
		if (Std.isOfType(chars, Array))
		{
			for (item in (cast chars : Array<Dynamic>))
			{
				if (item == null) continue;
				var name:String = Std.string(item);
				if (name != '' && name.toLowerCase() != 'none') return name;
			}
		}
		return getString(line, ['character', 'char', 'characterId'], '');
	}

	function codenameEventName(event:Dynamic):String
	{
		var named:String = getString(event, ['name', 'event', 'eventName', 'e'], '');
		if (named != '') return named;
		var type:Dynamic = getField(event, 'type');
		if (type == null) return '';
		if (Std.isOfType(type, Int) || Std.isOfType(type, Float))
			switch (Std.int(safeNumber(type, -999)))
			{
				case -1: return 'HScript Call';
				case 0: return 'Unknown Codename Event';
				case 1: return 'Camera Movement';
				case 2: return 'BPM Change';
				case 3: return 'Alt Animation Toggle';
			}
		return 'Codename Event Type ' + Std.string(type);
	}

	function normalizeTimeChanges(raw:Dynamic, defaultBpm:Float):Array<Dynamic>
	{
		var out:Array<Dynamic> = [];
		if (!Std.isOfType(raw, Array)) return out;
		for (row in (cast raw : Array<Dynamic>))
		{
			var t = hasField(row, 'beat') ? beatsToMs(readNumber(row, ['beat'], 0), defaultBpm) : readNumber(row, ['time', 'timestamp', 'startTime', 't'], 0) * timeMultiplier;
			var bpm = readNumber(row, ['bpm', 'BPM', 'b'], defaultBpm);
			if (bpm > 0) out.push({time: t, bpm: bpm});
		}
		out.sort(function(a:Dynamic, b:Dynamic):Int return a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		return out;
	}

	function buildLegacySong(data:Dynamic):Dynamic
	{
		var sections:Array<Dynamic> = [];
		var notes:Array<Dynamic> = cast data.notes;
		var sourceSections:Array<Dynamic> = cast data.sections;
		var hasSourceSections:Bool = data.hasSourceSections == true && sourceSections != null && sourceSections.length > 0;
		var maxTime:Float = 0;
		for (note in notes) maxTime = Math.max(maxTime, safeNumber(getField(note, 'time'), 0));

		if (hasSourceSections)
		{
			for (meta in sourceSections)
			{
				var section:Dynamic = cloneJsonObject(meta);
				Reflect.setField(section, 'sectionNotes', []);
				if (!hasField(section, 'lengthInSteps')) Reflect.setField(section, 'lengthInSteps', 16);
				if (!hasField(section, 'mustHitSection')) Reflect.setField(section, 'mustHitSection', true);
				sections.push(section);
			}
			for (note in notes)
			{
				var idx:Int = Std.int(getField(note, 'sourceSection'));
				if (idx < 0 || idx >= sections.length) idx = timeToSection(safeNumber(getField(note, 'time'), 0), data.bpm, data.timeChanges);
				while (idx >= sections.length) sections.push(makeSection(true, 100, false));
				appendLegacyNote(sections[idx], note);
			}
		}
		else
		{
			var bpmChanges:Array<Dynamic> = cast data.timeChanges;
			var start:Float = 0;
			var previousBpm:Float = safeNumber(data.bpm, 100);
			var index:Int = 0;
			while (start <= maxTime + 1 && index < 10000)
			{
				var thisBpm = bpmAtTime(start, previousBpm, bpmChanges);
				var duration:Float = 240000 / Math.max(1, thisBpm);
				var sectionEnd:Float = start + duration;
				var section:Dynamic = makeSection(true, thisBpm, index > 0 && thisBpm != previousBpm);
				var playerCount:Int = 0;
				var opponentCount:Int = 0;
				for (note in notes)
				{
					var t = safeNumber(getField(note, 'time'), 0);
					if (t >= start && t < sectionEnd)
					{
						if (Std.int(getField(note, 'lane')) < 4) playerCount++ else opponentCount++;
					}
				}
				Reflect.setField(section, 'mustHitSection', playerCount >= opponentCount);
				sections.push(section);
				for (note in notes)
				{
					var t = safeNumber(getField(note, 'time'), 0);
					if (t >= start && (t < sectionEnd || (index == 0 && maxTime == 0))) appendLegacyNote(section, note);
				}
				if (index > 0 && Math.abs(thisBpm - previousBpm) > 0.001) previousBpm = thisBpm;
				start = sectionEnd;
				index++;
			}
			if (bpmChanges != null)
			{
				for (change in bpmChanges)
				{
					var t:Float = safeNumber(getField(change, 'time'), 0);
					if (t > 0 && t % (240000 / Math.max(1, safeNumber(data.bpm, 100))) > 12)
						conversionWarnings.push('A BPM change at ' + Std.int(t) + ' ms is not aligned to a legacy section boundary; it was approximated to the next section.');
				}
			}
		}

		var song:Dynamic = {
			song: Std.string(data.song),
			bpm: safeNumber(data.bpm, 100),
			speed: safeNumber(data.speed, 1),
			needsVoices: data.needsVoices != false,
			offset: safeNumber(data.offset, 0),
			player1: Std.string(data.player1),
			player2: Std.string(data.player2),
			gfVersion: Std.string(data.gfVersion),
			stage: Std.string(data.stage),
			arrowSkin: Std.string(data.arrowSkin),
			splashSkin: Std.string(data.splashSkin),
			gameOverChar: Std.string(data.gameOverChar),
			gameOverSound: Std.string(data.gameOverSound),
			gameOverLoop: Std.string(data.gameOverLoop),
			gameOverEnd: Std.string(data.gameOverEnd),
			disableNoteRGB: data.disableNoteRGB == true,
			notes: sections,
			events: cast data.events
		};
		return song;
	}

	function appendLegacyNote(section:Dynamic, note:Dynamic):Void
	{
		var rows:Array<Dynamic> = cast getField(section, 'sectionNotes');
		if (rows == null)
		{
			rows = [];
			Reflect.setField(section, 'sectionNotes', rows);
		}
		var lane:Int = Std.int(safeNumber(getField(note, 'lane'), 0));
		var baseLane:Int = lane % 4;
		var isPlayer:Bool = lane < 4;
		var mustHit:Bool = getBool(section, ['mustHitSection'], true);
		var encodedLane:Int = (isPlayer == mustHit) ? baseLane : baseLane + 4;
		rows.push([
			safeNumber(getField(note, 'time'), 0),
			encodedLane,
			safeNumber(getField(note, 'length'), 0),
			getString(note, ['type'], '')
		]);
	}

	function makeSection(mustHit:Bool, bpm:Float, change:Bool):Dynamic
	{
		var out:Dynamic = {
			sectionNotes: [],
			lengthInSteps: 16,
			mustHitSection: mustHit,
			bpm: bpm,
			changeBPM: change,
			altAnim: false,
			gfSection: false
		};
		return out;
	}

	function timeToSection(time:Float, bpm:Float, changes:Array<Dynamic>):Int
	{
		var index:Int = 0;
		var start:Float = 0;
		var current:Float = bpm;
		while (index < 10000)
		{
			current = bpmAtTime(start, current, changes);
			var next = start + 240000 / Math.max(1, current);
			if (time < next) return index;
			start = next;
			index++;
		}
		return index;
	}

	function bpmAtTime(time:Float, base:Float, changes:Array<Dynamic>):Float
	{
		var bpm = base;
		if (changes == null) return bpm;
		for (change in changes)
		{
			var at = safeNumber(getField(change, 'time'), 0);
			if (at <= time + 0.01) bpm = safeNumber(getField(change, 'bpm'), bpm);
			else break;
		}
		return bpm;
	}

	function updateReport(?failure:String):Void
	{
		var count:Int = normalized != null && Std.isOfType(getField(normalized, 'notes'), Array) ? (cast getField(normalized, 'notes') : Array<Dynamic>).length : 0;
		var eventCount:Int = normalized != null && Std.isOfType(getField(normalized, 'events'), Array) ? countGroupedEvents(cast getField(normalized, 'events')) : 0;
		var report:Array<String> = [];
		report.push('Detected source: ' + sourceFormat + '     Target: Psych ' + targetVersion);
		report.push('Song: ' + (normalized != null ? Std.string(getField(normalized, 'song')) : '(unknown)') + '     Base BPM: ' + (normalized != null ? Std.string(getField(normalized, 'bpm')) : '—'));
		var bpmChanges:Dynamic = normalized == null ? null : getField(normalized, 'timeChanges');
		var bpmChangeCount:Int = Std.isOfType(bpmChanges, Array) ? (cast bpmChanges : Array<Dynamic>).length : 0;
		report.push('Timing normalized to milliseconds (source time multiplier x' + (normalized != null ? Std.string(getField(normalized, 'timeMultiplier')) : '1') + ')     BPM changes: ' + bpmChangeCount + '     Lane mapping: 0–3 BF/player / 4–7 Dad-side (GF + extra lines marked by note type)');
		var outputNoteCount:Int = countOutputNotes(outputData);
		report.push('Notes: ' + count + ' normalized / ' + outputNoteCount + ' in output     Skipped notes: ' + droppedNotes);
		report.push('Events: ' + eventCount + ' normalized     Skipped events: ' + droppedEvents + '     Output bytes: ' + (outputJson == null ? 0 : outputJson.length));
		if (failure != null) report.push(failure);
		var warns:Array<String> = conversionWarnings == null ? [] : conversionWarnings;
		for (warning in warns) report.push('WARNING: ' + warning);
		if (warns.length == 0 && failure == null) report.push('No conversion warnings were raised by the current importer. Manual playtest is still recommended.');

		reportLines = [];
		for (line in report) appendWrappedReportLine(reportLines, line, 150);
		reportScroll = 0;
		renderReportPage();
	}

	function appendWrappedReportLine(output:Array<String>, line:String, maxChars:Int):Void
	{
		if (line == null || line.length == 0)
		{
			output.push(' ');
			return;
		}
		var remaining:String = line;
		while (remaining.length > maxChars)
		{
			var splitAt:Int = remaining.lastIndexOf(' ', maxChars);
			if (splitAt < Std.int(maxChars * 0.55)) splitAt = maxChars;
			output.push(remaining.substr(0, splitAt));
			remaining = remaining.substr(splitAt);
			while (remaining.length > 0 && (remaining.charAt(0) == ' ' || remaining.charAt(0) == '\t'))
				remaining = remaining.substr(1);
		}
		output.push(remaining);
	}

	function renderReportPage():Void
	{
		if (reportText == null) return;
		if (reportLines == null) reportLines = [];
		var start:Int = Std.int(Math.max(0, Math.min(reportScroll, Math.max(0, reportLines.length - REPORT_VISIBLE_LINES))));
		reportScroll = start;
		var end:Int = Std.int(Math.min(reportLines.length, start + REPORT_VISIBLE_LINES));
		reportText.text = reportLines.length == 0 ? 'Waiting for input.' : reportLines.slice(start, end).join('\n');
		if (reportScrollText != null)
		{
			var firstLine = reportLines.length == 0 ? 0 : start + 1;
			var lastLine = end;
			reportScrollText.text = 'Lines $firstLine–$lastLine / ${reportLines.length}   •   Mouse wheel or ↑ / ↓ while over report to scroll';
		}
	}

	function scrollReport(delta:Int):Void
	{
		if (reportLines == null || reportLines.length <= REPORT_VISIBLE_LINES) return;
		var next = reportScroll + delta;
		var maxScroll = reportLines.length - REPORT_VISIBLE_LINES;
		if (next < 0) next = 0;
		if (next > maxScroll) next = maxScroll;
		if (next != reportScroll)
		{
			reportScroll = next;
			renderReportPage();
		}
	}

	function countOutputNotes(data:Dynamic):Int
	{
		if (data == null) return 0;
		var chart = data;
		var nested = getField(data, 'song');
		if (nested != null && !Std.isOfType(nested, String) && hasField(nested, 'notes')) chart = nested;
		var raw = getField(chart, 'notes');
		if (!Std.isOfType(raw, Array)) return 0;
		var rows:Array<Dynamic> = cast raw;
		var count:Int = 0;
		for (row in rows)
		{
			var sectionNotes = getField(row, 'sectionNotes');
			if (Std.isOfType(sectionNotes, Array)) count += (cast sectionNotes : Array<Dynamic>).length;
			else count++;
		}
		return count;
	}

	function countGroupedEvents(events:Array<Dynamic>):Int
	{
		var count:Int = 0;
		for (row in events)
		{
			if (!Std.isOfType(row, Array)) continue;
			var eventRow:Array<Dynamic> = cast row;
			if (eventRow.length < 2 || !Std.isOfType(eventRow[1], Array)) continue;
			var subEvents:Array<Dynamic> = cast eventRow[1];
			count += subEvents.length;
		}
		return count;
	}

	function renderPreview():Void
	{
		clearPreviewNotes();
		drawEmptyGrid();
		var notes:Array<Dynamic> = cast getField(normalized, 'notes');
		if (notes == null || notes.length == 0) return;
		var maxTime:Float = 1;
		for (note in notes) maxTime = Math.max(maxTime, safeNumber(getField(note, 'time'), 0) + safeNumber(getField(note, 'length'), 0));
		var plotX = PREVIEW_X + 50;
		var plotY = PREVIEW_Y + 38;
		var plotW = PREVIEW_W - 70;
		var plotH = PREVIEW_H - 52;
		var laneH = plotH / 8;
		var shown:Int = 0;
		for (note in notes)
		{
			if (shown >= 220) break;
			var time = safeNumber(getField(note, 'time'), 0);
			var lane = Std.int(Math.max(0, Math.min(7, safeNumber(getField(note, 'lane'), 0))));
			var length = safeNumber(getField(note, 'length'), 0);
			var x:Float = plotX + (time / maxTime) * plotW;
			var y:Float = plotY + lane * laneH + 2;
			var width:Float = Math.max(4, (length / maxTime) * plotW);
			width = Math.min(width, plotX + plotW - x);
			var color:Int = lane < 4 ? 0xFF4AA3FF : 0xFFFF9B57;
			var sprite = new FlxSprite(x, y).makeGraphic(Std.int(Math.max(4, width)), Std.int(Math.max(8, laneH - 4)), color);
			previewSprites.push(sprite);
			add(sprite);
			shown++;
		}
		if (notes.length > shown)
		{
			var more = new FlxText(PREVIEW_X + 12, PREVIEW_Y + PREVIEW_H - 20, PREVIEW_W - 24,
				'Showing first $shown of ${notes.length} notes in preview.', 11);
			more.color = 0xFFB8C4D3;
			previewSprites.push(cast more);
			add(more);
		}
	}

	function drawEmptyGrid():Void
	{
		var plotX = PREVIEW_X + 50;
		var plotY = PREVIEW_Y + 38;
		var plotW = PREVIEW_W - 70;
		var plotH = PREVIEW_H - 52;
		for (i in 0...9)
		{
			var line = new FlxSprite(plotX, plotY + i * plotH / 8).makeGraphic(Std.int(plotW), 1, 0xFF303C4C);
			previewSprites.push(line);
			add(line);
		}
		for (i in 0...9)
		{
			var line = new FlxSprite(plotX + i * plotW / 8, plotY).makeGraphic(1, Std.int(plotH), 0xFF26313F);
			previewSprites.push(line);
			add(line);
		}
		for (lane in 0...8)
		{
			var laneText = new FlxText(PREVIEW_X + 8, plotY + lane * plotH / 8 + 2, 36, 'L$lane', 11);
			laneText.color = lane < 4 ? 0xFF70B8FF : 0xFFFFB985;
			previewSprites.push(cast laneText);
			add(laneText);
		}
	}

	function clearPreviewNotes():Void
	{
		for (item in previewSprites)
		{
			remove(item, true);
			item.destroy();
		}
		previewSprites = [];
	}

	override function update(elapsed:Float):Void
	{
		if (controls.BACK && !leaving) goBack();
		if (reportFrame != null && FlxG.mouse.overlaps(reportFrame))
		{
			if (FlxG.mouse.wheel != 0) scrollReport(-FlxG.mouse.wheel);
			if (controls.UI_UP_P) scrollReport(-1);
			if (controls.UI_DOWN_P) scrollReport(1);
		}
		super.update(elapsed);
	}

	function setStatus(message:String, isError:Bool = false):Void
	{
		if (statusText != null)
		{
			statusText.text = message;
			statusText.color = isError ? FlxColor.RED : 0xFF77D6A3;
		}
		trace('[Chart Converter] ' + message);
	}

	function attachDropListener():Void
	{
		#if sys
		try
		{
			var app = Application.current;
			if (app == null || app.window == null)
			{
				setStatus('Window drop receiver unavailable. Use Open Chart JSON instead.', true);
				return;
			}
			dropWindow = app.window;
			dropHandler = function(path:String):Void
			{
				if (path == null || path.length == 0) return;
				trace('[Chart Converter] OS dropped file: ' + path);
				pendingDropPaths.push(path);
				if (dropBatchTimer == null) dropBatchTimer = new FlxTimer();
				dropBatchTimer.cancel();
				dropBatchTimer.start(0.18, function(_):Void
				{
					var batch = pendingDropPaths.copy();
					pendingDropPaths = [];
					processDropBatch(batch);
				});
			};
			// Use Lime's typed file-drop signal directly. Reflection can fail to find
			// generated/accessor-backed signal fields on some Lime/OpenFL builds.
			dropWindow.onDropFile.add(dropHandler);
			dropListenerAttached = true;
			trace('[Chart Converter] Lime OS drag-and-drop listener attached.');
		}
		catch (e:Dynamic)
		{
			trace('[Chart Converter] Could not attach OS drag/drop listener: ' + Std.string(e));
			setStatus('Drag-and-drop could not attach on this build. Use Open Chart JSON.', true);
		}
		#end
	}

	override function destroy():Void
	{
		#if sys
		try
		{
			if (dropWindow != null && dropHandler != null)
				dropWindow.onDropFile.remove(dropHandler);
			dropListenerAttached = false;
		}
		catch (e:Dynamic) {}
		#end
		clearPreviewNotes();
		super.destroy();
	}

	static function getField(value:Dynamic, key:String):Dynamic
	{
		if (value == null) return null;
		try { return Reflect.field(value, key); } catch (e:Dynamic) return null;
	}

	static function hasField(value:Dynamic, key:String):Bool
	{
		if (value == null) return false;
		try { return Reflect.hasField(value, key); } catch (e:Dynamic) return false;
	}

	static function getString(value:Dynamic, keys:Array<String>, fallback:String):String
	{
		for (key in keys)
		{
			var field = getField(value, key);
			if (field != null && Std.string(field) != '') return Std.string(field);
		}
		return fallback;
	}

	static function readNumber(value:Dynamic, keys:Array<String>, fallback:Float):Float
	{
		for (key in keys)
			if (hasField(value, key)) return safeNumber(getField(value, key), fallback);
		return fallback;
	}

	static function getFloat(value:Dynamic, keys:Array<String>, fallback:Float):Float
	{
		return readNumber(value, keys, fallback);
	}

	static function getBool(value:Dynamic, keys:Array<String>, fallback:Bool):Bool
	{
		for (key in keys)
		{
			var field = getField(value, key);
			if (field == null) continue;
			if (Std.isOfType(field, Bool)) return field;
			var s = Std.string(field).toLowerCase();
			if (s == 'true' || s == '1') return true;
			if (s == 'false' || s == '0') return false;
		}
		return fallback;
	}

	static function safeNumber(value:Dynamic, fallback:Float):Float
	{
		if (value == null) return fallback;
		var n:Float = Std.parseFloat(Std.string(value));
		return Math.isNaN(n) ? fallback : n;
	}

	static function beatsToMs(beats:Float, bpm:Float):Float
	{
		return beats * 60000 / Math.max(1, bpm);
	}

	static function cloneJsonObject(value:Dynamic):Dynamic
	{
		if (value == null) return {};
		try { return Json.parse(Json.stringify(value)); } catch (e:Dynamic) return {};
	}

	static function safeSongName(value:String):String
	{
		var name = value == null || value.length == 0 ? 'converted-chart' : value.toLowerCase();
		var out = '';
		for (i in 0...name.length)
		{
			var c = name.charAt(i);
			if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_') out += c;
			else if (c == ' ' || c == '.') out += '-';
		}
		while (out.indexOf('--') >= 0) out = out.replace('--', '-');
		return out.length == 0 ? 'converted-chart' : out;
	}
}
