import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/individual_bar.dart';

class AppBarChart extends StatefulWidget {
  final List<IndividualBar>? data;

  const AppBarChart({super.key, this.data});

  @override
  State<AppBarChart> createState() => _AppBarChartState();
}

class _AppBarChartState extends State<AppBarChart> {
  final FocusNode _chartFocusNode = FocusNode(debugLabel: 'Chart container');

  bool _isContainerFocused = false;
  bool _isBarNavigationActive = false;
  int _selectedBarIndex = 0;

  List<IndividualBar> get _data => widget.data ?? const [];

  @override
  void initState() {
    super.initState();
    _chartFocusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    final hasFocus = _chartFocusNode.hasFocus;
    if (_isContainerFocused != hasFocus) {
      setState(() {
        _isContainerFocused = hasFocus;
        if (!hasFocus) {
          _isBarNavigationActive = false;
        }
      });
    }
  }

  @override
  void dispose() {
    _chartFocusNode.removeListener(_handleFocusChange);
    _chartFocusNode.dispose();
    super.dispose();
  }

  void _enterBarNavigation() {
    if (_data.isEmpty) return;

    setState(() {
      _isBarNavigationActive = true;
      _selectedBarIndex = 0;
    });
  }

  void _exitBarNavigation() {
    if (!_isBarNavigationActive) return;

    setState(() {
      _isBarNavigationActive = false;
    });

    // Keep focus on the chart container, not on an individual bar.
    _chartFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;

    final maxCount = _data.fold<int>(
      0,
      (maximum, item) =>
          item.blockedCount > maximum ? item.blockedCount : maximum,
    );

    final maxY = maxCount == 0 ? 10.0 : (maxCount * 1.2).ceilToDouble();

    return PopScope(
      canPop: !_isBarNavigationActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isBarNavigationActive) {
          _exitBarNavigation();
        }
      },
      child: Focus(
        focusNode: _chartFocusNode,
        canRequestFocus: true,
        onKeyEvent: (node, event) {
          final key = event.logicalKey;

          final isActivationKey =
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter;

          final isBackKey =
              key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.backspace;

          // LEVEL 1: Chart container has focus.
          if (!_isBarNavigationActive) {
            if (isActivationKey) {
              if (event is KeyDownEvent) {
                _enterBarNavigation();
              }
              return KeyEventResult.handled;
            }

            // Let the parent dashboard handle directional navigation.
            return KeyEventResult.ignored;
          }

          // LEVEL 2: Navigate between individual bars.
          if (isBackKey) {
            if (event is KeyDownEvent) {
              _exitBarNavigation();
            }
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.arrowLeft) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (_data.isNotEmpty) {
                setState(() {
                  _selectedBarIndex = (_selectedBarIndex - 1).clamp(
                    0,
                    _data.length - 1,
                  );
                });
              }
            }
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.arrowRight) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (_data.isNotEmpty) {
                setState(() {
                  _selectedBarIndex = (_selectedBarIndex + 1).clamp(
                    0,
                    _data.length - 1,
                  );
                });
              }
            }
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown) {
            // Keep focus trapped inside the chart during bar navigation.
            return KeyEventResult.handled;
          }

          if (isActivationKey) {
            // OK/Enter while already browsing bars does not exit the mode.
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _isContainerFocused ? colors.primary : colors.border,
              width: _isContainerFocused ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();

                          if (value != index.toDouble() ||
                              index < 0 ||
                              index >= _data.length) {
                            return const SizedBox.shrink();
                          }

                          final interval = _data.length > 7
                              ? (_data.length / 6).ceil()
                              : 1;
                          final isVisible =
                              (index % interval == 0) ||
                              (index == _data.length - 1);
                          if (_data.length > 7 &&
                              isVisible &&
                              index != _data.length - 1 &&
                              (_data.length - 1 - index) < 3) {
                            return const SizedBox.shrink();
                          }
                          if (!isVisible) {
                            return const SizedBox.shrink();
                          }

                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              DateFormat('dd MMM')
                                  .format(_data[index].timestamp),
                              style: typo.bodySmall.copyWith(
                                color: colors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        if (group.x < 0 || group.x >= _data.length) {
                          return null;
                        }

                        final item = _data[group.x];

                        return BarTooltipItem(
                          '${DateFormat('dd MMM:').format(item.timestamp)} ${item.blockedCount} blocked',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: List.generate(_data.length, (index) {
                    final item = _data[index];
                    final isSelected =
                        _isBarNavigationActive && index == _selectedBarIndex;
                    final isZero = item.blockedCount == 0;

                    // Subtle baseline marker height for zero-count dates (1.8% of maxY).
                    // This produces a consistent ~3-5px visual tick on the baseline at any scale.
                    final zeroMarkerY = maxY * 0.018;

                    final double rodY = isZero
                        ? zeroMarkerY
                        : (item.blockedCount.toDouble() < zeroMarkerY * 1.5
                              ? zeroMarkerY * 1.5
                              : item.blockedCount.toDouble());
                    final Color rodColor = isZero
                        ? (isSelected
                              ? colors.primary
                              : colors.textSecondary.withValues(alpha: 0.25))
                        : (isSelected ? colors.primary : colors.primary200);
                    return BarChartGroupData(
                      x: index,
                      showingTooltipIndicators: isSelected ? [0] : [],
                      barRods: [
                        BarChartRodData(
                          toY: rodY,
                          color: rodColor,
                          width: isSelected ? 34.0 : 30.0,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 180),
              ),
              if (_data.isEmpty || maxCount == 0)
                Text(
                  'No blocked activity in the last 7 days',
                  style: typo.bodySmall.copyWith(
                    color: colors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
