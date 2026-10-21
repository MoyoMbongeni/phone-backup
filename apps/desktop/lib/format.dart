import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

String formatDate(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

String formatDuration(Duration duration) => duration.inSeconds < 60
    ? '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s'
    : '${duration.inMinutes} min ${duration.inSeconds % 60} s';

enum FileKind { image, video, audio, text, document, archive, other }

const _kindsByExtension = {
  FileKind.image: {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'},
  FileKind.video: {'mp4', 'mov', 'mkv', 'avi', '3gp', 'webm', 'm4v'},
  FileKind.audio: {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'wma'},
  FileKind.text: {'txt', 'md', 'csv', 'json', 'log', 'xml', 'ini', 'vcf'},
  FileKind.document: {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt'},
  FileKind.archive: {'zip', 'rar', '7z', 'tar', 'gz'},
};

FileKind kindOf(String name) {
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  for (final entry in _kindsByExtension.entries) {
    if (entry.value.contains(extension)) return entry.key;
  }
  return FileKind.other;
}

IconData iconFor(FileKind kind) => switch (kind) {
      FileKind.image => Icons.image_outlined,
      FileKind.video => Icons.movie_outlined,
      FileKind.audio => Icons.music_note_outlined,
      FileKind.text => Icons.description_outlined,
      FileKind.document => Icons.article_outlined,
      FileKind.archive => Icons.folder_zip_outlined,
      FileKind.other => Icons.insert_drive_file_outlined,
    };

IconData iconForEvent(EventType type) => switch (type) {
      EventType.vaultCreated => Icons.shield_outlined,
      EventType.passwordChanged => Icons.password,
      EventType.sourceAdded => Icons.create_new_folder_outlined,
      EventType.fileAdded => Icons.add_circle_outline,
      EventType.fileModified => Icons.edit_outlined,
      EventType.fileMoved => Icons.drive_file_move_outline,
      EventType.fileDeleted => Icons.delete_outline,
      EventType.snapshot => Icons.task_alt,
    };

String describeEvent(VaultEvent event, Map<String, SourceInfo> sources) {
  final info = event.info ?? const {};
  final sourceName = sources[event.source]?.name ?? 'a folder';
  return switch (event.type) {
    EventType.vaultCreated => 'Vault created',
    EventType.passwordChanged => 'Password changed',
    EventType.sourceAdded => 'Started backing up "${info['name']}" (${info['location']})',
    EventType.fileAdded => 'Added ${event.path}',
    EventType.fileModified => 'Changed ${event.path}',
    EventType.fileMoved => 'Moved ${event.fromPath} → ${event.path}',
    EventType.fileDeleted => 'Deleted ${event.path} (still kept in the vault)',
    EventType.snapshot => 'Backup of "$sourceName" finished: '
        '${info['added']} added, ${info['modified']} changed, '
        '${info['moved']} moved, ${info['deleted']} deleted',
  };
}
