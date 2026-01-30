# 🚀 Плагин Pushed Messaging для Flutter

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)

**Flutter плагин для интеграции с Multipushed Messaging**

[![pub version](https://img.shields.io/pub/v/flutter_pushed_messaging.svg)](https://pub.dev/packages/flutter_pushed_messaging)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[🌐 Официальный сайт](https://multipushed.ru) • [📚 Документация](https://www.pushed.ru/docs/solution/)

</div>

---

## 🚀 Начало работы

### 📦 Установка

Добавьте в ваш `pubspec.yaml`:

```yaml
dependencies:
  flutter_pushed_messaging: ^1.7.0
```

Затем выполните:

```bash
flutter pub get
```

### 📥 Импорт

```dart
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';
```

---

## 📚 Содержание

- [🚀 Начало работы](#getting-started)
- [📱 Настройка iOS](#ios-setup)
  - [📦 Базовая настройка iOS](#basic-ios-setup)
  - [🔧 Notification Service Extension](#notification-service-extension)
  - [🔐 Настройка Keychain Sharing](#keychain-sharing)
- [🤖 Настройка Android](#android-setup)
  - [🔥 Настройка Firebase (FCM)](#firebase-fcm)
  - [📱 Настройка Huawei (HMS)](#huawei-hms)
  - [🏪 Настройка RuStore](#rustore-setup)
- [💡 Реализация](#implementation)
- [🐛 Решение проблем](#troubleshooting)
- [❓ Часто задаваемые вопросы](#faq)

---

<a id="getting-started"></a>

## 🚀 Начало работы

### 📦 Установка

Добавьте в ваш `pubspec.yaml`:

```yaml
dependencies:
  flutter_pushed_messaging: ^1.7.0
```

Затем выполните:

```bash
flutter pub get
```

### 📥 Импорт

```dart
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';
```

---

<a id="ios-setup"></a>

## 📱 Настройка iOS

### 📦 Базовая настройка iOS

<a id="basic-ios-setup"></a>

> ⚠️ **Предварительные условия**: Убедитесь, что ваше iOS приложение правильно настроено для push-уведомлений

#### 🔧 Необходимые возможности

1. **Откройте ваш iOS проект в Xcode**
2. **Добавьте возможность Push Notifications:**
   - Выберите ваш target → **Signing & Capabilities**
   - Нажмите **+ Capability** → **Push Notifications**
3. **Добавьте возможность Background Modes:**
   - Нажмите **+ Capability** → **Background Modes**
   - Включите **Remote notifications**

#### 📝 Настройка AppDelegate

Добавьте это в ваш `AppDelegate.swift` (или `AppDelegate.m`) в метод `didFinishLaunchingWithOptions`:

```swift
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
}
```

<div align="center">

### 🎯 **Следующий шаг: Настройка iOS Extension** 👇

</div>

---

<a id="notification-service-extension"></a>

## 🔧 Настройка Notification Service Extension

> 🚀 **Зачем это нужно?** Notification Service Extension обеспечивает расширенные возможности push-уведомлений, такие как богатый контент, отслеживание доставки и фоновая обработка.

### 📱 Создание Extension

#### Шаг 1: Создание Extension Target

1. 🎯 **В Xcode:** `File` → `New` → `Target` → **`Notification Service Extension`**
2. 📝 **Product Name:** `extension` (или ваше предпочитаемое имя)
3. ✅ **Нажмите:** `Activate`
4. 🔄 **Язык:** Swift (рекомендуется)

#### Шаг 2: Настройка Build Phases

> ⚠️ **Критический шаг:** Это обеспечивает правильный порядок сборки

1. 🎯 **Выберите ваш основной target** (Runner)
2. 📂 **Перейдите:** на вкладку `Build Phases`
3. 🔄 **Перетащите:** `Embed Foundation Extensions` **НАД** `Run Script`

#### Шаг 3: Конфигурация сборки

```bash
# Выполните это в корне вашего проекта
flutter build ios --config-only
```

### 🛠️ Настройка Podfile

#### Редактируйте `ios/Podfile`

Найдите эту строку:
```ruby
flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
```

**Добавьте сразу после:**
```ruby
target 'extension' do  # ← Замените 'extension' на фактическое имя вашего extension
  inherit! :search_paths
end 
```

#### Обновите зависимости

```bash
cd ios
pod update
```

### 📝 Реализация NotificationService.swift

Замените содержимое вашего `NotificationService.swift` на:

```swift
import UserNotifications
import flutter_pushed_messaging

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        // 🚀 Эта магическая строка обеспечивает расширенные возможности
        FlutterPushedMessagingPlugin.confirmExtension(userInfo: request.content.userInfo)
        
        if let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Вызывается непосредственно перед завершением extension системой.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
```

---

<a id="keychain-sharing"></a>

## 🔐 Настройка Keychain Sharing

> ⚠️ **КРИТИЧЕСКИ ВАЖНО:** Без этой настройки Extension не будет работать!

### 🎯 Настройка основного приложения

1. 📱 **Выберите ваш основной app target** (Runner)
2. 🔧 **Перейдите в:** `Signing & Capabilities`
3. ➕ **Добавьте:** `Keychain Sharing` capability
4. 🔑 **Добавьте keychain group:** `$(AppIdentifierPrefix)com.yourcompany.yourapp.shared`

### 🔧 Настройка Extension

1. 🎯 **Выберите ваш extension target**
2. 🔧 **Перейдите в:** `Signing & Capabilities`
3. ➕ **Добавьте:** `Keychain Sharing` capability
4. 🔑 **Добавьте ТУ ЖЕ keychain group:** `$(AppIdentifierPrefix)com.yourcompany.yourapp.shared`

> 💡 **Совет профи:** Замените `com.yourcompany.yourapp` на ваш фактический bundle identifier

---

<a id="android-setup"></a>

## 🤖 Настройка Android

### 🔥 Настройка Firebase (FCM)

<a id="firebase-fcm"></a>

> 📱 **Для приложений Google Play Store и большинства Android устройств**

#### Шаг 1: Зависимости в корневом `build.gradle`

Добавьте в `android/build.gradle`:

```gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.3.15'
        classpath 'com.google.firebase:firebase-crashlytics-gradle:2.8.1'
        // ... другие зависимости
    }
}
```

#### Шаг 2: Добавьте файл конфигурации

1. 📥 **Скачайте** `google-services.json` из Firebase Console
2. 📂 **Поместите в:** папку `android/app/`

#### Шаг 3: Конфигурация на уровне приложения

Добавьте в `android/app/build.gradle`:

```gradle
apply plugin: 'com.google.gms.google-services'
apply plugin: 'com.google.firebase.crashlytics'
```

---

### 📱 Настройка Huawei (HMS)

<a id="huawei-hms"></a>

> 📱 **Для устройств Huawei и AppGallery**

#### Шаг 1: Конфигурация корневого `build.gradle`

Добавьте в `android/build.gradle`:

```gradle
buildscript {
    repositories {
        maven { url 'https://developer.huawei.com/repo/' }
        // ... другие репозитории
    }
    dependencies {
        classpath 'com.huawei.agconnect:agcp:1.5.2.300'
        // ... другие зависимости
    }
}

allprojects {
    repositories {
        maven { url 'https://developer.huawei.com/repo/' }
        // ... другие репозитории
    }
}
```

#### Шаг 2: Добавьте файл конфигурации

1. 📥 **Скачайте** `agconnect-services.json` из Huawei Developer Console
2. 📂 **Поместите в:** папку `android/app/`

#### Шаг 3: Конфигурация на уровне приложения

Добавьте в `android/app/build.gradle`:

```gradle
dependencies {
    implementation 'com.huawei.agconnect:agconnect-core:1.5.2.300'
    // ... другие зависимости
}

apply plugin: 'com.huawei.agconnect'
```

---

### 🏪 Настройка RuStore

<a id="rustore-setup"></a>

> 🇷🇺 **Для RuStore (российский магазин приложений)**

Добавьте в `android/app/src/main/AndroidManifest.xml`:

```xml
<application>
    <!-- ... другие настройки ... -->
    
    <meta-data
        android:name="ru.rustore.sdk.pushclient.project_id"
        android:value="Ваш RuStore project ID" />
        
</application>
```

---

## 💡 Реализация

<a id="implementation"></a>

### 🚀 Обработчик фоновых сообщений

```dart
import 'package:flutter_pushed_messaging/flutter_pushed_messaging.dart';

// 🔄 Этот обработчик работает даже когда ваше приложение закрыто
@pragma('vm:entry-point')
Future<void> backgroundMessage(Map<dynamic, dynamic> message) async {
    print("📱 Получено фоновое сообщение: $message");
    
    // 💡 Добавьте вашу логику здесь
    // - Сохранение в локальную базу данных
    // - Показ кастомного уведомления
    // - Обновление значка приложения
}
```

### 🎯 Настройка основного приложения

```dart
void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // 🚀 Инициализация плагина
    await FlutterPushedMessaging.init(
        backgroundMessage,
        notificationChannel: "messages",     // 🤖 Только для Android
        askPermissions: true,               // 📱 Автозапрос разрешений
        loggerEnabled: false,               // 🐛 Включите для отладки
        applicationId: "YOUR_APP_ID",       // 🔑 Кастомный идентификатор (опционально)
    );
    
    // 🔑 Получение уникального токена клиента
    print("🔑 Токен клиента: ${FlutterPushedMessaging.token}");
    
    runApp(const MyApp());
}
```

### 📱 Прослушивание сообщений

```dart
class _MyAppState extends State<MyApp> {
    @override
    void initState() {
        super.initState();
        _setupMessageListeners();
    }
    
    void _setupMessageListeners() {
        // 📥 Сообщения на переднем плане
        FlutterPushedMessaging.onMessage().listen((message) {
            print("📱 Сообщение на переднем плане: $message");
            
            // 💡 Обработка сообщения
            _showInAppNotification(message);
        });
        
        // 📊 Статус соединения
        FlutterPushedMessaging.onStatus().listen((status) {
            print("📡 Статус: $status");
            
            switch (status) {
                case ServiceStatus.active:
                    print("✅ Подключен и готов!");
                    break;
                case ServiceStatus.disconnected:
                    print("🔄 Переподключение...");
                    break;
                case ServiceStatus.notActive:
                    print("❌ Сервис неактивен");
                    break;
            }
        });
    }
}
```

### 👆 Обработка кликов по уведомлениям

Плагин позволяет отслеживать, когда пользователь нажимает на уведомление, чтобы открыть приложение. Это ключевая функция для реализации диплинков и навигации внутри приложения по пушу.

Логика разделена на два сценария:

1.  **Приложение было закрыто (убито):** Используйте `getInitialMessage()`.
2.  **Приложение было в фоне (свёрнуто):** Используйте стрим `onMessageOpenedApp()`.

#### `Future<Map?> getInitialMessage()`

Этот метод возвращает `Future`, который содержит данные уведомления, запустившего приложение из полностью закрытого состояния. Его следует вызывать один раз при инициализации вашего приложения.

#### `Stream<Map> onMessageOpenedApp()`

Этот стрим генерирует событие каждый раз, когда пользователь нажимает на уведомление, и приложение переходит из фонового режима в активный.

#### 📝 Пример реализации

Лучше всего разместить эту логику в `initState` вашего главного виджета:

```dart
@override
void initState() {
    super.initState();
    _setupMessageListeners();
    _setupClickListeners(); // <-- Добавляем обработку кликов
}

void _setupClickListeners() async {
    // Сценарий 1: Приложение было закрыто
    final initialMessage = await FlutterPushedMessaging.getInitialMessage();
    if (initialMessage != null) {
        print("📱 Приложение открыто по клику на уведомление (из закрытого состояния): $initialMessage");
        // 💡 Здесь ваша логика для диплинка
        // handleDeepLink(initialMessage);
    }

    // Сценарий 2: Приложение было в фоне
    FlutterPushedMessaging.onMessageOpenedApp().listen((message) {
        print("📱 Приложение открыто по клику на уведомление (из фона): $message");
        // 💡 Здесь ваша логика для диплинка
        // handleDeepLink(message);
    });
}
```

> 💡 **Совет:** Для `iOS`, в текущей реализации, оба сценария (клик из фона и получение сообщения в фоне) приходят в один стрим `onMessage()`. Разделение на `getInitialMessage` и `onMessageOpenedApp` в первую очередь актуально для **Android**.


### 🔐 Ручной запрос разрешений

```dart
// 📱 Запрос разрешений вручную при необходимости
await FlutterPushedMessaging.askPermissions(
    askNotificationPermission: true,    // 📱 Показ уведомлений
    askBackgroundPermission: true,      // 🤖 Фоновая работа Android
);
```

---

## 🐛 Решение проблем

<a id="troubleshooting"></a>

### 📱 Проблемы iOS

<details>
<summary><strong>🔴 Extension не работает</strong></summary>

**Проверьте эти распространенные проблемы:**

1. ✅ **Keychain Sharing** - Оба target должны иметь одинаковую keychain group
2. ✅ **Build Phases** - Extension должен быть встроен перед Run Script
3. ✅ **Podfile** - Extension target должен быть правильно настроен
4. ✅ **Подписание** - Extension должен быть правильно подписан

**Шаги отладки:**
```bash
# Очистка и пересборка
flutter clean
cd ios && pod install
flutter build ios --config-only
```
</details>

<details>
<summary><strong>🔴 Push-уведомления не появляются</strong></summary>

**Проверьте:**

1. ✅ **Capabilities** - Push Notifications + Background Modes включены
2. ✅ **APNs Сертификат** - Действителен и не истек
3. ✅ **Device Token** - Приложение успешно зарегистрировано для push
4. ✅ **Payload** - Формат сообщения правильный

**Тестирование:**
```bash
# Проверка регистрации устройства
print("Токен: ${FlutterPushedMessaging.token}");
```
</details>

### 🤖 Проблемы Android

<details>
<summary><strong>🔴 FCM не работает</strong></summary>

**Проверьте:**

1. ✅ **google-services.json** - Файл существует в `android/app/`
2. ✅ **Плагины** - Оба плагина применены в app/build.gradle
3. ✅ **Зависимости** - Правильные версии в build.gradle
4. ✅ **Имя пакета** - Совпадает с Firebase проектом

**Отладка:**
```bash
# Проверка Firebase регистрации
flutter run --verbose
# Ищите логи "Firebase"
```
</details>

<details>
<summary><strong>🔴 Фоновые сообщения не работают</strong></summary>

**Проверьте:**

1. ✅ **Оптимизация батареи** - Приложение не ограничено
2. ✅ **Автозапуск** - Приложению разрешен автоматический запуск
3. ✅ **Фоновый обработчик** - Правильно зарегистрирован
4. ✅ **Разрешения** - Разрешение фоновой работы предоставлено

**Тестирование:**
```dart
// Добавьте логирование в фоновый обработчик
@pragma('vm:entry-point')
Future<void> backgroundMessage(Map<dynamic, dynamic> message) async {
    print("ФОНОВОЕ: $message"); // Это должно появиться в логах
}
```
</details>

### 🛠️ Общие проблемы

<details>
<summary><strong>🔴 Плагин не инициализируется</strong></summary>

**Распространенные причины:**

1. ❌ **Отсутствует await** - Убедитесь, что используете await для init()
2. ❌ **Неправильное время** - Инициализируйте после WidgetsFlutterBinding
3. ❌ **Зависимости** - Убедитесь, что все зависимости установлены

**Правильная инициализация:**
```dart
void main() async {
    WidgetsFlutterBinding.ensureInitialized(); // ← Важно!
    await FlutterPushedMessaging.init(
        backgroundMessage,
        notificationChannel: "messages",     // 🤖 Только для Android
        askPermissions: true,               // 📱 Автозапрос разрешений
        loggerEnabled: false,               // 🐛 Включите для отладки
        applicationId: "YOUR_APP_ID",       // 🔑 Кастомный идентификатор (опционально)
    ); // ← Await!
    runApp(MyApp());
}
```
</details>

---

<a id="faq"></a>

## ❓ Часто задаваемые вопросы

<details>
<summary><strong>📱 Могу ли я настроить внешний вид уведомлений?</strong></summary>

Да! На Android вы можете настроить канал уведомлений. На iOS настройте payload в вашем NotificationService extension.

</details>

<details>
<summary><strong>🔄 Как обрабатывать обновления приложения?</strong></summary>

Токен остается действительным после обновлений приложения. Однако всегда тестируйте push-уведомления после крупных обновлений для обеспечения совместимости.

</details>

<details>
<summary><strong>🌍 Работает ли это с несколькими языками?</strong></summary>

Да! Плагин поддерживает интернационализацию. Настройте содержимое уведомлений на основе локали пользователя.

</details>

<details>
<summary><strong>📊 Могу ли я отслеживать доставку сообщений?</strong></summary>

Да! Используйте Extension на iOS и уведомления о доставке FCM на Android для отслеживания статуса доставки сообщений.

</details>

---

<div align="center">

### 🎉 **Всё готово!** 

**Ваше приложение теперь готово для получения push-уведомления** 🚀

Сделано с ❤️ командой [Multipushed](https://multipushed.ru)

---

[![⭐ Звезда на GitHub](https://img.shields.io/github/stars/yourusername/flutter_pushed_messaging?style=social)](https://github.com/PushedLab/Pushed.Messaging.Flutter.Plugin)
[![💬 Telegram](https://img.shields.io/badge/Telegram-Join-blue?logo=telegram&style=social)](https://t.me/pushed_ru)

</div>
