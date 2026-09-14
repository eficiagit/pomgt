import 'package:flutter/material.dart';

class DetailSection {
  const DetailSection({
    required this.label,
    required this.help,
    required this.icon,
    required this.child,
  });

  final String label;
  final String help;
  final IconData icon;
  final Widget child;
}

class DetailSections extends StatefulWidget {
  const DetailSections({super.key, required this.sections});

  final List<DetailSection> sections;

  @override
  State<DetailSections> createState() => _DetailSectionsState();
}

class _DetailSectionsState extends State<DetailSections> {
  var selected = 0;

  @override
  void didUpdateWidget(covariant DetailSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selected >= widget.sections.length) {
      selected = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: widget.sections.length,
      initialIndex: selected,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final section in widget.sections) Tab(text: section.label),
            ],
            onTap: (index) => setState(() => selected = index),
          ),
          const Divider(height: 1),
          Expanded(
            child: ClipRect(
              child: TabBarView(
                children: [
                  for (final section in widget.sections) section.child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
