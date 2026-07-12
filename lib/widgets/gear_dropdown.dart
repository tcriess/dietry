import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/gear.dart';

/// Picks the gear a workout was done with. Shared by the add and edit activity
/// forms. Always offers a "none" option — attribution is optional.
class GearDropdown extends StatelessWidget {
  final List<Gear> gear;
  final Gear? selected;
  final ValueChanged<Gear?> onChanged;

  const GearDropdown({
    super.key,
    required this.gear,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return DropdownButtonFormField<Gear?>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l.gearFieldLabel,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(value: null, child: Text(l.gearNone)),
        ...gear.map((g) => DropdownMenuItem(
              value: g,
              child: Row(
                children: [
                  Icon(g.category.icon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(g.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            )),
      ],
      onChanged: onChanged,
    );
  }
}
