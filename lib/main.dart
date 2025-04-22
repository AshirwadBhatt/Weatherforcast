import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weather App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String apiKey = 'fa4869371c46dcb8c5f2031318f21095';
  final String baseUrl = 'https://api.openweathermap.org/data/2.5';

  bool isLoading = true;
  String errorMessage = '';
  Map<String, dynamic> currentWeather = {};
  List<dynamic> hourlyForecast = [];
  List<dynamic> dailyForecast = [];
  String cityName = '';
  String countryCode = '';

  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;

  Map<String, dynamic> cachedData = {};
  DateTime lastFetchTime = DateTime.now().subtract(const Duration(hours: 1));

  @override
  void initState() {
    super.initState();
    _fetchWeatherWithLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchWeatherWithLocation() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        await _fetchWeatherData(
          lat: position.latitude,
          lon: position.longitude,
        );
      } else {
        setState(() {
          errorMessage = 'Location permission denied. Using default location.';
        });
        await _fetchWeatherData(cityName: 'London');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Error fetching location: $e';
      });
    }
  }

  Future<void> _fetchWeatherData(
      {String? cityName, double? lat, double? lon}) async {
    if (DateTime.now().difference(lastFetchTime).inMinutes < 10) {
      if (cachedData.isNotEmpty) {
        setState(() {
          currentWeather = cachedData['current'] ?? {};
          hourlyForecast = cachedData['hourly'] ?? [];
          dailyForecast = cachedData['daily'] ?? [];
          this.cityName = cachedData['cityName'] ?? '';
          countryCode = cachedData['countryCode'] ?? '';
          isLoading = false;
        });
        return;
      }
    }

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      String currentWeatherUrl;
      String forecastUrl;

      if (cityName != null) {
        currentWeatherUrl =
        '$baseUrl/weather?q=${Uri.encodeComponent(cityName)}&appid=$apiKey&units=metric';
        forecastUrl =
        '$baseUrl/forecast?q=${Uri.encodeComponent(cityName)}&appid=$apiKey&units=metric';
      } else if (lat != null && lon != null) {
        currentWeatherUrl =
        '$baseUrl/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric';
        forecastUrl =
        '$baseUrl/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=metric';
      } else {
        throw Exception('Either city name or coordinates must be provided');
      }

      final currentResponse = await http.get(Uri.parse(currentWeatherUrl));
      if (currentResponse.statusCode == 200) {
        currentWeather = json.decode(currentResponse.body);
        this.cityName = currentWeather['name'];
        countryCode = currentWeather['sys']['country'];
      } else {
        throw Exception('Failed to fetch current weather data: ${currentResponse.statusCode}');
      }

      final forecastResponse = await http.get(Uri.parse(forecastUrl));
      if (forecastResponse.statusCode == 200) {
        final forecastData = json.decode(forecastResponse.body);

        hourlyForecast = forecastData['list'].take(8).toList();

        Map<String, dynamic> dailyData = {};
        for (var item in forecastData['list']) {
          final date = DateTime.fromMillisecondsSinceEpoch(item['dt'] * 1000);
          final dateKey = DateFormat('yyyy-MM-dd').format(date);

          if (!dailyData.containsKey(dateKey)) {
            dailyData[dateKey] = {
              'date': date,
              'temp_min': item['main']['temp_min'],
              'temp_max': item['main']['temp_max'],
              'weather': item['weather'][0],
            };
          } else {
            dailyData[dateKey]['temp_min'] =
                min(dailyData[dateKey]['temp_min'], item['main']['temp_min']);
            dailyData[dateKey]['temp_max'] =
                max(dailyData[dateKey]['temp_max'], item['main']['temp_max']);
          }
        }

        dailyForecast = dailyData.values.take(5).toList();

        cachedData = {
          'current': currentWeather,
          'hourly': hourlyForecast,
          'daily': dailyForecast,
          'cityName': this.cityName,
          'countryCode': countryCode,
        };
        lastFetchTime = DateTime.now();
      } else {
        throw Exception('Failed to fetch forecast data: ${forecastResponse.statusCode}');
      }

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Error fetching weather data: $e';
      });
    }
  }

  double min(double a, double b) => a < b ? a : b;
  double max(double a, double b) => a > b ? a : b;

  String getWeatherIcon(String iconCode, {bool large = false}) {
    return 'https://openweathermap.org/img/wn/$iconCode${large ? '@2x' : ''}.png';
  }

  String formatDate(DateTime date, {bool short = false}) {
    if (short) {
      return DateFormat('E').format(date);
    }
    return DateFormat('EEEE, MMMM d').format(date);
  }

  String formatTime(DateTime time) {
    return DateFormat('h:mm a').format(time);
  }

  List<Color> _getBackgroundGradient() {
    if (currentWeather.isEmpty) {
      return [Colors.blue.shade300, Colors.blue.shade700];
    }

    final weatherId = currentWeather['weather'][0]['id'];
    final isNight = _isNightTime();

    if (weatherId == 800) {
      return isNight
          ? [Colors.indigo.shade900, Colors.black]
          : [Colors.blue.shade300, Colors.blue.shade700];
    } else if (weatherId >= 801 && weatherId <= 804) {
      return isNight
          ? [Colors.blueGrey.shade900, Colors.blueGrey.shade700]
          : [Colors.blueGrey.shade200, Colors.blueGrey.shade500];
    } else if ((weatherId >= 500 && weatherId <= 531) ||
        (weatherId >= 300 && weatherId <= 321)) {
      return isNight
          ? [Colors.indigo.shade800, Colors.indigo.shade400]
          : [Colors.blueGrey.shade400, Colors.blueGrey.shade700];
    } else if (weatherId >= 200 && weatherId <= 232) {
      return [Colors.grey.shade800, Colors.grey.shade600];
    } else if (weatherId >= 600 && weatherId <= 622) {
      return isNight
          ? [Colors.blueGrey.shade800, Colors.blueGrey.shade600]
          : [Colors.grey.shade300, Colors.grey.shade500];
    } else if (weatherId >= 701 && weatherId <= 781) {
      return [Colors.blueGrey.shade300, Colors.blueGrey.shade500];
    }

    return [Colors.blue.shade300, Colors.blue.shade700];
  }

  bool _isNightTime() {
    if (currentWeather.isEmpty) return false;

    final sunset = DateTime.fromMillisecondsSinceEpoch(
        currentWeather['sys']['sunset'] * 1000);
    final sunrise = DateTime.fromMillisecondsSinceEpoch(
        currentWeather['sys']['sunrise'] * 1000);
    final now = DateTime.now();

    return now.isAfter(sunset) || now.isBefore(sunrise);
  }

  String _getWeatherEmoji() {
    if (currentWeather.isEmpty) return '';

    final weatherId = currentWeather['weather'][0]['id'];

    if (weatherId == 800) {
      return _isNightTime() ? '🌙 Clear' : '☀️ Clear';
    } else if (weatherId >= 801 && weatherId <= 804) {
      return _isNightTime() ? '☁️ Cloudy' : '⛅ Cloudy';
    } else if (weatherId >= 500 && weatherId <= 531) {
      return '🌧️ Rainy';
    } else if (weatherId >= 200 && weatherId <= 232) {
      return '⛈️ Thunderstorm';
    } else if (weatherId >= 600 && weatherId <= 622) {
      return '❄️ Snowy';
    } else if (weatherId >= 300 && weatherId <= 321) {
      return '🌦️ Drizzle';
    } else if (weatherId >= 701 && weatherId <= 781) {
      return '🌫️ Foggy';
    }

    return currentWeather['weather'][0]['main'];
  }

  void _startSearch() {
    setState(() {
      isSearching = true;
    });
  }

  void _cancelSearch() {
    setState(() {
      isSearching = false;
      _searchController.clear();
    });
  }

  void _performSearch() {
    if (_searchController.text.isNotEmpty) {
      _fetchWeatherData(cityName: _searchController.text);
      setState(() {
        isSearching = false;
      });
      _searchController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          if (cityName.isNotEmpty) {
            await _fetchWeatherData(cityName: cityName);
          } else {
            await _fetchWeatherWithLocation();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _getBackgroundGradient(),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      if (!isSearching) ...[
                        IconButton(
                          icon: const Icon(Icons.my_location,
                              color: Colors.white),
                          onPressed: _fetchWeatherWithLocation,
                        ),
                        Expanded(
                          child: Text(
                            isLoading
                                ? 'Loading...'
                                : '$cityName, $countryCode',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search, color: Colors.white),
                          onPressed: _startSearch,
                        ),
                      ] else ...[
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'Search city...',
                              hintStyle: TextStyle(
                                  color: Colors.white.withAlpha(179)),
                              border: InputBorder.none,
                            ),
                            style: const TextStyle(color: Colors.white),
                            cursorColor: Colors.white,
                            onSubmitted: (_) => _performSearch(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search, color: Colors.white),
                          onPressed: _performSearch,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: _cancelSearch,
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: isLoading
                      ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                      : errorMessage.isNotEmpty
                      ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            errorMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchWeatherWithLocation,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  )
                      : ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    children: [
                      Card(
                        color: Colors.black.withAlpha(64),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          formatDate(DateTime.now()),
                                          style: TextStyle(
                                            color: Colors.white
                                                .withAlpha(230),
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${currentWeather['main']['temp'].round()}°C',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 64,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          _getWeatherEmoji(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Feels like ${currentWeather['main']['feels_like'].round()}°C',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withAlpha(230),
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Image.network(
                                    getWeatherIcon(
                                      currentWeather['weather'][0]['icon'],
                                      large: true,
                                    ),
                                    width: 100,
                                    height: 100,
                                    errorBuilder: (context, error,
                                        stackTrace) =>
                                    const Icon(Icons.error,
                                        color: Colors.white,
                                        size: 100),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceAround,
                                children: [
                                  _buildWeatherInfo(
                                    Icons.water_drop,
                                    '${currentWeather['main']['humidity']}%',
                                    'Humidity',
                                  ),
                                  _buildWeatherInfo(
                                    Icons.air,
                                    '${currentWeather['wind']['speed']} m/s',
                                    'Wind',
                                  ),
                                  _buildWeatherInfo(
                                    Icons.visibility,
                                    '${(currentWeather['visibility'] / 1000).toStringAsFixed(1)} km',
                                    'Visibility',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'HOURLY FORECAST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: hourlyForecast.length,
                          itemBuilder: (context, index) {
                            final hourData = hourlyForecast[index];
                            final time = DateTime
                                .fromMillisecondsSinceEpoch(
                              hourData['dt'] * 1000,
                            );
                            return Container(
                              width: 80,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(26),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: [
                                  Text(
                                    index == 0
                                        ? 'Now'
                                        : formatTime(time),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Image.network(
                                    getWeatherIcon(
                                        hourData['weather'][0]['icon']),
                                    width: 40,
                                    height: 40,
                                    errorBuilder: (context, error,
                                        stackTrace) =>
                                    const Icon(Icons.error,
                                        color: Colors.white,
                                        size: 40),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${hourData['main']['temp'].round()}°C',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '5-DAY FORECAST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        color: Colors.black.withAlpha(64),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: dailyForecast.map((day) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 100,
                                      child: Text(
                                        formatDate(day['date'],
                                            short: true),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        children: [
                                          Image.network(
                                            getWeatherIcon(
                                                day['weather']['icon']),
                                            width: 40,
                                            height: 40,
                                            errorBuilder: (context,
                                                error, stackTrace) =>
                                            const Icon(Icons.error,
                                                color: Colors.white,
                                                size: 40),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            day['weather']['main'],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${day['temp_min'].round()}°',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withAlpha(179),
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${day['temp_max'].round()}°',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (currentWeather.isNotEmpty &&
                          currentWeather.containsKey('sys'))
                        Card(
                          color: Colors.black.withAlpha(64),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Text(
                                  'SUN & MOON',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildSunMoonInfo(
                                      Icons.wb_sunny,
                                      'Sunrise',
                                      formatTime(DateTime
                                          .fromMillisecondsSinceEpoch(
                                        currentWeather['sys']['sunrise'] *
                                            1000,
                                      )),
                                    ),
                                    _buildSunMoonInfo(
                                      Icons.nightlight,
                                      'Sunset',
                                      formatTime(DateTime
                                          .fromMillisecondsSinceEpoch(
                                        currentWeather['sys']['sunset'] *
                                            1000,
                                      )),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherInfo(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withAlpha(179),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildSunMoonInfo(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withAlpha(179),
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}