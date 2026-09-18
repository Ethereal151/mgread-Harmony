import 'package:flutter/material.dart';

import 'package:mg_read/features/discovery/application/batch_search.dart';

/// Opens the source-version selector used by the content detail sheet.
Future<void> showSourceContentVariantPicker(
  BuildContext context, {
  required List<SourceSearchHit> variants,
  required String selectedPluginId,
  required String selectedContentId,
  required Future<void> Function(SourceSearchHit variant) onSelected,
}) async {
  final selected = await showModalBottomSheet<SourceSearchHit>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: variants.length,
        itemBuilder: (context, index) {
          final variant = variants[index];
          return ListTile(
            leading: Icon(index == 0 ? Icons.star_rounded : Icons.source_outlined),
            title: Text(variant.source.displayName),
            subtitle: Text(variant.content.title),
            trailing: variant.content.id == selectedContentId && variant.pluginId == selectedPluginId
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.of(context).pop(variant),
          );
        },
      ),
    ),
  );
  if (selected == null || (selected.pluginId == selectedPluginId && selected.content.id == selectedContentId)) return;
  await onSelected(selected);
}
