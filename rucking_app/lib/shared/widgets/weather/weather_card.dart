import 'package:flutter/material.dart';
import '../../../core/models/weather.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Weather forecast card widget showing current conditions and forecast
class WeatherCard extends StatelessWidget {
  final Weather? weather;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const WeatherCard({
    super.key,
    this.weather,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.wb_sunny, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Weather Forecast',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isLoading) ...[
                  const Spacer(),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Content
            if (isLoading && weather == null)
              _buildLoadingContent()
            else if (errorMessage != null)
              _buildErrorContent()
            else if (weather?.currentWeather != null)
              _buildWeatherContent()
            else
              _buildNoDataContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingContent() {
    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(
          'Loading weather forecast...',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textDarkSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                errorMessage ?? 'Unable to load weather data',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoDataContent() {
    return Text(
      'Weather information will be available closer to your planned date.',
      style: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textDarkSecondary,
      ),
    );
  }

  Widget _buildWeatherContent() {
    final current = weather!.currentWeather!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current conditions
        _buildCurrentWeather(current),

        // Hourly forecast if available
        if (weather!.hourlyForecast?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          _buildHourlyForecast(),
        ],

        // Daily forecast if available
        if (weather!.dailyForecast?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          _buildDailyForecast(),
        ],
      ],
    );
  }

  Widget _buildCurrentWeather(CurrentWeather current) {
    final conditionCode = current.conditionCode ?? 800;
    final temperature = current.temperature?.round() ?? 0;
    final feelsLike = current.temperatureApparent?.round() ?? 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Weather icon and temperature
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conditionCode.weatherIcon,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${temperature}°',
                        style: AppTextStyles.headlineMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Feels like ${feelsLike}°',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                conditionCode.description,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Weather details
        Expanded(
          flex: 3,
          child: _buildWeatherDetails(current),
        ),
      ],
    );
  }

  Widget _buildWeatherDetails(CurrentWeather current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (current.humidity != null)
          _buildDetailRow(
            icon: Icons.water_drop,
            label: 'Humidity',
            value: '${(current.humidity! * 100).round()}%',
          ),
        if (current.windSpeed != null)
          _buildDetailRow(
            icon: Icons.air,
            label: 'Wind',
            value: '${current.windSpeed!.round()} km/h',
          ),
        if (current.uvIndex != null)
          _buildDetailRow(
            icon: Icons.wb_sunny_outlined,
            label: 'UV Index',
            value: current.uvIndex!.round().toString(),
          ),
        if (current.visibility != null)
          _buildDetailRow(
            icon: Icons.visibility,
            label: 'Visibility',
            value: '${current.visibility!.round()} km',
          ),
      ],
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: AppColors.textDarkSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textDarkSecondary,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyForecast() {
    final hourly =
        weather!.hourlyForecast!.take(8).toList(); // Show next 8 hours

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hourly Forecast',
          style: AppTextStyles.titleSmall.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: hourly.length,
            itemBuilder: (context, index) {
              final forecast = hourly[index];
              final time = forecast.forecastStart;
              final temp = forecast.temperature?.round() ?? 0;
              final condition = forecast.conditionCode ?? 800;

              return Container(
                width: 60,
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                  children: [
                    Text(
                      time != null ? '${time.hour}:00' : '--',
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      condition.weatherIcon,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${temp}°',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDailyForecast() {
    final daily = weather!.dailyForecast!.take(5).toList(); // Show next 5 days

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '5-Day Forecast',
          style: AppTextStyles.titleSmall.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...daily.map((forecast) {
          final date = forecast.forecastStart;
          final high = forecast.temperatureMax?.round() ?? 0;
          final low = forecast.temperatureMin?.round() ?? 0;
          final condition = forecast.conditionCode ?? 800;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    date != null ? _getDayName(date) : '--',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  condition.weatherIcon,
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    condition.description,
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
                Text(
                  '${high}°/${low}°',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  String _getDayName(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(date.year, date.month, date.day);

    final difference = targetDay.difference(today).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';

    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}
