import 'package:file_selector/file_selector.dart';

/// The native folder and save pickers. Integration tests swap in answers,
/// since a test cannot click inside a Windows dialog.
class FileDialogs {
  const FileDialogs();

  Future<String?> pickDirectory({required String confirmButtonText}) =>
      getDirectoryPath(confirmButtonText: confirmButtonText);

  Future<String?> pickSaveLocation({required String suggestedName}) async =>
      (await getSaveLocation(suggestedName: suggestedName))?.path;
}

FileDialogs fileDialogs = const FileDialogs();
