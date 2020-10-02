import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:csv/csv.dart';

class CSVParser {
  final String fieldDelimiter;
  final String strings;
  final List<List<dynamic>> lines;

  CSVParser(this.strings, {this.fieldDelimiter = ','})
      : lines = CsvToListConverter()
      .convert(strings, fieldDelimiter: fieldDelimiter);

  List getLanguages() {
    return lines.first.sublist(1, lines.first.length);
  }

  Map<String, dynamic> getLanguageMap(String localeName) {
    final indexLocale = lines.first.indexOf(localeName);

    var translations = <String, dynamic>{};
    for (var i = 1; i < lines.length; i++) {
      translations.addAll({lines[i][0]: lines[i][indexLocale]});
    }
    return translations;
  }
}

const _preservedKeywords = [
  'few',
  'many',
  'one',
  'other',
  'two',
  'zero',
  'male',
  'female',
];

void main(List<String> args) {
  if (_isHelpCommand(args)) {
    _printHelperDisplay();
  } else {
    final GenerateOptions options = _generateOption(args);
    if (options.format == "csv_and_keys") {
      final GenerateOptions csvOptions = _generateOption(args);
      csvOptions.format = "csv";
      handleLangFiles(csvOptions);
      final GenerateOptions csvKeysOptions = _generateOption(args);
      csvKeysOptions.format = "csv_keys";
      csvKeysOptions.outputFile = "codegen_loader_keys.g.dart";
      handleLangFiles(csvKeysOptions);
    } else {
      handleLangFiles(options);
    }
  }
}

bool _isHelpCommand(List<String> args) {
  return args.length == 1 && (args[0] == '--help' || args[0] == '-h');
}

void _printHelperDisplay() {
  var parser = _generateArgParser(null);
  print(parser.usage);
}

GenerateOptions _generateOption(List<String> args) {
  var generateOptions = GenerateOptions();
  var parser = _generateArgParser(generateOptions);
  parser.parse(args);
  return generateOptions;
}

ArgParser _generateArgParser(GenerateOptions generateOptions) {
  var parser = ArgParser();

  parser.addOption('source-dir',
      abbr: 'S',
      defaultsTo: 'resources/langs',
      callback: (String x) => generateOptions.sourceDir = x,
      help: 'Folder containing localization files');

  parser.addOption('source-file',
      abbr: 's',
      callback: (String x) => generateOptions.sourceFile = x,
      help: 'File to use for localization');

  parser.addOption('output-dir',
      abbr: 'O',
      defaultsTo: 'lib/generated',
      callback: (String x) => generateOptions.outputDir = x,
      help: 'Output folder stores for the generated file');

  parser.addOption('output-file',
      abbr: 'o',
      defaultsTo: 'codegen_loader.g.dart',
      callback: (String x) => generateOptions.outputFile = x,
      help: 'Output file name');

  parser.addOption('format',
      abbr: 'f',
      defaultsTo: 'csv_and_keys',
      callback: (String x) => generateOptions.format = x,
      help: 'Support json, csv or keys formats',
      allowed: ['json', 'keys', 'csv', 'csv_keys', 'csv_and_keys']);

  return parser;
}

class GenerateOptions {
  String sourceDir;
  String sourceFile;
  String templateLocale;
  String outputDir;
  String outputFile;
  String format;

  @override
  String toString() {
    return 'format: $format sourceDir: $sourceDir sourceFile: $sourceFile outputDir: $outputDir outputFile: $outputFile';
  }
}

void handleLangFiles(GenerateOptions options) async {
  final current = Directory.current;
  /// s
  final source = Directory.fromUri(Uri.parse(options.sourceDir));
  /// o
  final output = Directory.fromUri(Uri.parse(options.outputDir));
  /// S
  final sourcePath = Directory(path.join(current.path, source.path));

  if (!await sourcePath.exists()) {
    printError('Source path does not exist');
    return;
  }

  var files = await dirContents(sourcePath);
  if (options.sourceFile != null) {
    final sourceFile = File(path.join(source.path, options.sourceFile));
    if (!await sourceFile.exists()) {
      printError('Source file does not exist (${sourceFile.toString()})');
      return;
    }
    files = [sourceFile];
  } else {
    //filtering format
    files = files.where((f) => f.path.contains('.json')).toList();
  }

  final outputPath =
  Directory(path.join(current.path, output.path, options.outputFile));
  if (files.isNotEmpty) {
    generateFile(files, outputPath, options.format);
  } else {
    printError('Source path empty');
  }
}

Future<List<FileSystemEntity>> dirContents(Directory dir) {
  var files = <FileSystemEntity>[];
  var completer = Completer<List<FileSystemEntity>>();
  var lister = dir.list(recursive: false);
  lister.listen((file) => files.add(file),
      onDone: () => completer.complete(files));
  return completer.future;
}

void generateFile(
    List<FileSystemEntity> files, Directory outputPath, String format) async {
  var generatedFile = File(outputPath.path);
  if (!generatedFile.existsSync()) {
    generatedFile.createSync(recursive: true);
  }

  var classBuilder = StringBuffer();

  switch (format) {
    case 'json':
      await _writeJson(classBuilder, files);
      break;
    case 'keys':
      await _writeKeys(classBuilder, files);
      break;
    case 'csv':
      await _writeCsv(classBuilder, files);
      break;
    case 'csv_keys':
      await _writeCsvKeys(classBuilder, files);
      break;
    default:
      printError('Format not support');
  }

  classBuilder.writeln('}');
  generatedFile.writeAsStringSync(classBuilder.toString());

  printInfo('All done! File generated in ${outputPath.path}');
}

Future _writeKeys(StringBuffer classBuilder, List<FileSystemEntity> files) async {
  var file = '''
// DO NOT EDIT. This is code generated via package:easy_localization/generate.dart

abstract class LocaleKeys {
''';

  final fileData = File(files.first.path);

  Map<String, dynamic> translations =
      json.decode(await fileData.readAsString());

  file += _resolve(translations);

  classBuilder.writeln(file);
}


Future _writeCsvKeys(StringBuffer classBuilder, List<FileSystemEntity> files) async {
  var file = '''
// DO NOT EDIT. This is code generated via package:easy_localization/generate.dart

abstract class LocaleKeys {
''';

  classBuilder.writeln(file);
  final fileData = File(files.first.path);
  CSVParser csvParser = CSVParser(await fileData.readAsString());
  for (List<dynamic> line in csvParser.lines) {
    if(line != csvParser.lines[0]) {
      final List<String> stringLine = line.map((dynamic e) => e as String).toList();
      final String key = stringLine[0].replaceAll('.', '_');
      classBuilder.writeln('  static const String $key = \'${stringLine[0]}\';\n');
    }
  }
}


String _resolve(Map<String, dynamic> translations, [String accKey]) {
  var fileContent = '';

  final sortedKeys = translations.keys.toList();

  for (var key in sortedKeys) {
    if (translations[key] is Map) {
      var nextAccKey = key;
      if (accKey != null) {
        nextAccKey = '$accKey.$key';
      }

      fileContent += _resolve(translations[key], nextAccKey);
    }

    if (!_preservedKeywords.contains(key)) {
      accKey != null
          ? fileContent +=
              '  static const ${accKey.replaceAll('.', '_')}\_$key = \'$accKey.$key\';\n'
          : fileContent += '  static const $key = \'$key\';\n';
    }
  }

  return fileContent;
}

Future _writeJson(
    StringBuffer classBuilder, List<FileSystemEntity> files) async {
  var gFile = '''
// DO NOT EDIT. This is code generated via package:easy_localization/generate.dart

// ignore_for_file: prefer_single_quotes

import 'dart:ui';

import 'package:easy_localization/easy_localization.dart' show AssetLoader;

class CodegenLoader extends AssetLoader{
  const CodegenLoader();

  @override
  Future<Map<String, dynamic>> load(String fullPath, Locale locale ) {
    return Future.value(mapLocales[locale.toString()]);
  }

  ''';

  final listLocales = [];

  for (var file in files) {
    final localeName =
        path.basename(file.path).replaceFirst('.json', '').replaceAll('-', '_');
    listLocales.add('"$localeName": $localeName');
    final fileData = File(file.path);

    Map<String, dynamic> data = json.decode(await fileData.readAsString());

    final mapString = JsonEncoder.withIndent('  ').convert(data);
    gFile += 'static const Map<String,dynamic> $localeName = $mapString;\n';
  }

  gFile +=
      'static const Map<String, Map<String,dynamic>> mapLocales = \{${listLocales.join(', ')}\};';
  classBuilder.writeln(gFile);
}

Future _writeCsv(StringBuffer classBuilder, List<FileSystemEntity> files) async {
  var gFile = '''
// DO NOT EDIT. This is code generated via package:easy_localization/generate.dart

// ignore_for_file: prefer_single_quotes

import 'dart:ui';

import 'package:easy_localization/easy_localization.dart' show AssetLoader;

class CodegenLoader extends AssetLoader{
  const CodegenLoader();

  @override
  Future<Map<String, dynamic>> load(String fullPath, Locale locale ) {
    return Future.value(mapLocales[locale.toString()]);
  }

  ''';
  classBuilder.writeln(gFile);
  List<String> listLocales = List();
  final fileData = File(files.first.path);

  CSVParser csvParser = CSVParser(await fileData.readAsString());

  List listLangs = csvParser.getLanguages();
  for (String localeName in listLangs) {
    listLocales.add('"$localeName": $localeName');
    String mapString = JsonEncoder.withIndent("    ").convert(csvParser.getLanguageMap(localeName)).replaceAll("\\n", "\u{1F601}");

    classBuilder.writeln('  static const Map<String,dynamic> $localeName = <String, dynamic>${mapString};\n');
  }

  classBuilder.writeln('  static const Map<String, Map<String,dynamic>> mapLocales = \{${listLocales.join(', ')}\};');
}

void printInfo(String info) {
  print('\u001b[32measy localization: $info\u001b[0m');
}

void printError(String error) {
  print('\u001b[31m[ERROR] easy localization: $error\u001b[0m');
}
