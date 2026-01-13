// lib/widgets/stats/earnings_chart.dart

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

class EarningsChart extends StatelessWidget {
  final Map<DateTime, double> earningsOverTime;
  final DateTime startDate;
  final DateTime endDate;

  const EarningsChart({
    Key? key,
    required this.earningsOverTime,
    required this.startDate,
    required this.endDate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<ChartData> chartData = earningsOverTime.entries
        .map((entry) => ChartData(entry.key, entry.value))
        .toList();

    // Sort the data by date to ensure the chart displays correctly
    chartData.sort((a, b) => a.date.compareTo(b.date));

    if (chartData.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(child: Text('No earnings data available.')),
      );
    }

    return Container(
      margin: const EdgeInsets.all(8.0),
      height: 300, // Adjust the height as needed
      child: SfCartesianChart(
        title: ChartTitle(text: 'Earnings Over Time'),
        primaryXAxis: DateTimeAxis(
          minimum: startDate,
          maximum: endDate,
          intervalType: DateTimeIntervalType.days,
          dateFormat: DateFormat.MMMd(),
          majorGridLines: MajorGridLines(width: 0),
          labelRotation: -45,
          labelAlignment: LabelAlignment.start,
        ),
        primaryYAxis: NumericAxis(
          labelFormat: '{value} TRY',
          axisLine: AxisLine(width: 0),
          majorTickLines: MajorTickLines(size: 0),
        ),
        tooltipBehavior:
            TooltipBehavior(enable: true, format: 'point.x : point.y TRY'),
        zoomPanBehavior: ZoomPanBehavior(
          enablePinching: true,
          enablePanning: true,
          zoomMode: ZoomMode.x,
        ),
        series: <CartesianSeries<ChartData, DateTime>>[
          LineSeries<ChartData, DateTime>(
            dataSource: chartData,
            xValueMapper: (ChartData data, _) => data.date,
            yValueMapper: (ChartData data, _) => data.value,
            name: 'Earnings',
            markerSettings: MarkerSettings(
              isVisible: true,
              height: 8,
              width: 8,
              shape: DataMarkerType.circle,
            ),
            dataLabelSettings: DataLabelSettings(isVisible: false),
            color: Colors.blue, // Colorful line
            enableTooltip: true, // Enable interaction
            animationDuration: 1000,
          )
        ],
      ),
    );
  }
}

class ChartData {
  final DateTime date;
  final double value;

  ChartData(this.date, this.value);
}
