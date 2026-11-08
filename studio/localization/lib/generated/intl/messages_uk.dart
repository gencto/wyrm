// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a uk locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'uk';

  static String m0(n) => "${n} д тому";

  static String m1(n) => "${n} год тому";

  static String m2(n) => "${n} хв тому";

  static String m3(sites) => "просить ретранслювати: ${sites}";

  static String m4(driver) => "вбудований драйвер ${driver}";

  static String m5(site) => "підписано CA · ${site} CA";

  static String m6(id) => "Відкликати допуск ${id}?";

  static String m7(device) =>
      "Працює на ${device}; брокер не може його запустити чи зупинити.";

  static String m8(id) => "Параметри ${id}";

  static String m9(when) => "уперше ${when}";

  static String m10(address) => "з ${address}";

  static String m11(key) => "Перейти до ${key}";

  static String m12(id) => "Доступ для ${id}";

  static String m13(id) => "Історія параметрів ${id}";

  static String m14(name, broker) => "${name} встановлено на ${broker}.";

  static String m15(n) =>
      "${Intl.plural(n, one: 'уже ${n} лінк', few: 'уже ${n} лінки', other: 'уже ${n} лінків')}";

  static String m16(site) =>
      "Запускає і стежить ${site}: вбудовані драйвери і встановлені пакети. Їх можна зупинити, змінити, оновити й видалити.";

  static String m17(site) => "Лінки на ${site}";

  static String m18(id) => "Журнал ${id}";

  static String m19(level, have) => "Потрібно ${level} · у вас ${have}";

  static String m20(level) => "Потрібно ${level} · у вас є";

  static String m21(name) => "пакет ${name}";

  static String m22(n) =>
      "${Intl.plural(n, zero: 'без параметрів', one: '${n} параметр', few: '${n} параметри', other: '${n} параметрів')}";

  static String m23(rev) => "Параметри (ревізія ${rev}, JSON)";

  static String m24(name) => "${name} встановлено";

  static String m25(name) => "Встановлення ${name}…";

  static String m26(cn) => "Відхилити ${cn}?";

  static String m27(id) => "Видалити ${id}?";

  static String m28(action) => "Результат · ${action}";

  static String m29(what) => "повертає ${what}";

  static String m30(rev) => "Ревізія ${rev}";

  static String m31(rev) => "Ревізія ${rev} · діє";

  static String m32(rev) => "Повернути ревізію ${rev}?";

  static String m33(n) =>
      "${Intl.plural(n, one: '${n} рядок', few: '${n} рядки', other: '${n} рядків')}";

  static String m34(user) =>
      "Виконується як ${user}. Нічого більше в дереві не змінюється, якщо результат не використати.";

  static String m35(site) => "Працює на ${site}";

  static String m36(count) =>
      "${Intl.plural(count, zero: 'Немає підготовлених змін', one: '${count} підготовлена зміна', few: '${count} підготовлені зміни', other: '${count} підготовлених змін')}";

  static String m37(n, total) => "Крок ${n} з ${total}";

  static String m38(level) => "потрібно ${level}";

  static String m39(site) => "Дерево · ${site}";

  static String m40(site) => "через ${site}";

  static String m41(value) => "було ${value}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "_locale": MessageLookupByLibrary.simpleMessage("uk"),
    "aCustomPackage": MessageLookupByLibrary.simpleMessage("Власний пакет"),
    "acceptFirst": MessageLookupByLibrary.simpleMessage(
      "Спершу прийміть запитані права.",
    ),
    "acceptRequestedRights": MessageLookupByLibrary.simpleMessage(
      "Прийняти запитані права",
    ),
    "accepted": MessageLookupByLibrary.simpleMessage("прийнято"),
    "actComesWithWyrmd": MessageLookupByLibrary.simpleMessage(
      "Входить до wyrmd",
    ),
    "actComesWithWyrmdNote": MessageLookupByLibrary.simpleMessage(
      "Вбудований драйвер оновлюється разом із брокером.",
    ),
    "actDeauthorize": MessageLookupByLibrary.simpleMessage("Відкликати допуск"),
    "actDeauthorizeNote": MessageLookupByLibrary.simpleMessage(
      "Заблокувати зараз: права забрано, наступне з’єднання чекатиме в карантині. Дерево лишається.",
    ),
    "actEditParams": MessageLookupByLibrary.simpleMessage("Змінити параметри"),
    "actEditParamsNote": MessageLookupByLibrary.simpleMessage(
      "Параметри лінка. Зберігаються як нова ревізія.",
    ),
    "actGrant": MessageLookupByLibrary.simpleMessage("Надати доступ"),
    "actGrantNote": MessageLookupByLibrary.simpleMessage(
      "Читання або запис поза власною гілкою.",
    ),
    "actGrants": MessageLookupByLibrary.simpleMessage("Доступи"),
    "actGrantsNote": MessageLookupByLibrary.simpleMessage(
      "Лише власна гілка. Додайте читання або запис деінде.",
    ),
    "actParamsHistory": MessageLookupByLibrary.simpleMessage(
      "Історія параметрів",
    ),
    "actParamsHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Ревізії параметрів; поверніться до будь-якої.",
    ),
    "actRemoveForGood": MessageLookupByLibrary.simpleMessage(
      "Видалити назавжди",
    ),
    "actRemoveForGoodNote": MessageLookupByLibrary.simpleMessage(
      "Вилучити id: цей сертифікат більше не отримає прав. Новому пристрою потрібен новий сертифікат.",
    ),
    "actRemoveLink": MessageLookupByLibrary.simpleMessage("Видалити лінк"),
    "actRemoveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Зупиняє його і видаляє його дерево.",
    ),
    "actSecrets": MessageLookupByLibrary.simpleMessage("Секрети"),
    "actSecretsNote": MessageLookupByLibrary.simpleMessage(
      "Паролі й ключі, запечатані; більше не показуються.",
    ),
    "actStart": MessageLookupByLibrary.simpleMessage("Запустити"),
    "actStartNote": MessageLookupByLibrary.simpleMessage(
      "Запустити знову з останніми параметрами.",
    ),
    "actStartStopRestart": MessageLookupByLibrary.simpleMessage(
      "Запуск, зупинка, перезапуск",
    ),
    "actStop": MessageLookupByLibrary.simpleMessage("Зупинити"),
    "actStopNote": MessageLookupByLibrary.simpleMessage(
      "Лишається встановленим; його точки стають bad до запуску.",
    ),
    "actUpgrade": MessageLookupByLibrary.simpleMessage("Оновити"),
    "actUpgradeNote": MessageLookupByLibrary.simpleMessage(
      "Встановити новішу версію пакета.",
    ),
    "actUpgradeParamsLog": MessageLookupByLibrary.simpleMessage(
      "Оновлення, параметри, журнал",
    ),
    "actViewLog": MessageLookupByLibrary.simpleMessage("Журнал"),
    "actViewLogNote": MessageLookupByLibrary.simpleMessage(
      "Останні рядки і власний рівень журналу.",
    ),
    "addALink": MessageLookupByLibrary.simpleMessage("Додати лінк"),
    "addAnother": MessageLookupByLibrary.simpleMessage("Додати ще"),
    "agoDays": m0,
    "agoHours": m1,
    "agoMinutes": m2,
    "agoNow": MessageLookupByLibrary.simpleMessage("щойно"),
    "allowAllLinks": MessageLookupByLibrary.simpleMessage(
      "Допускати всі лінки",
    ),
    "allowAllLinksNote": MessageLookupByLibrary.simpleMessage(
      "Кожен новий CN цього CA одразу стає лінком, без схвалення. Витеклий сертифікат теж пройде.",
    ),
    "answerBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "answerFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "answerLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "answerName": MessageLookupByLibrary.simpleMessage("Назва"),
    "answerRights": MessageLookupByLibrary.simpleMessage("Права"),
    "answerRuns": MessageLookupByLibrary.simpleMessage("Працює"),
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Застосувати"),
    "approve": MessageLookupByLibrary.simpleMessage("Схвалити"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення допускає його як брокер нижче з указаними ретрансляціями. Спершу порівняйте ключ із його sys/upstream/<цей сайт>/key.",
    ),
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення робить його зовнішнім лінком із власною гілкою і токеном; скопіюйте токен на пристрій. Роутер перезавантажується приблизно на секунду. Відхилення відмовляє цьому CN надалі.",
    ),
    "asksToRelay": m3,
    "back": MessageLookupByLibrary.simpleMessage("Назад"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("До лінків"),
    "branchOrTag": MessageLookupByLibrary.simpleMessage("гілка або тег"),
    "bringOne": MessageLookupByLibrary.simpleMessage(
      "Оберіть файл або вкажіть, де пакет.",
    ),
    "brokerRefused": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив зміну; наступні не застосовано.",
    ),
    "brokerSays": MessageLookupByLibrary.simpleMessage("Брокер каже"),
    "builtIn": MessageLookupByLibrary.simpleMessage("вбудований"),
    "builtInDriver": m4,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Вбудований у wyrmd · нічого не завантажується",
    ),
    "caSigned": m5,
    "canDoNothing": MessageLookupByLibrary.simpleMessage(
      "нічого: ні читання, ні запису",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Скасувати"),
    "cannotReachGateway": MessageLookupByLibrary.simpleMessage(
      "Не вдалося з’єднатися з gateway",
    ),
    "catalogNote": MessageLookupByLibrary.simpleMessage(
      "Вбудований: у wyrmd, нічого не завантажується. Пакет: з індексу packages.repository, SHA-256 перевіряється; брокер показує лише пакети, які може встановити.",
    ),
    "changeAnswers": MessageLookupByLibrary.simpleMessage("Змінити відповіді"),
    "checkFailed": MessageLookupByLibrary.simpleMessage(
      "Пакет не пройшов перевірку: принесіть інший.",
    ),
    "checkYourConnection": MessageLookupByLibrary.simpleMessage(
      "Перевірте з’єднання та спробуйте ще раз.",
    ),
    "checkedHere": MessageLookupByLibrary.simpleMessage(
      "Перевірено тут; брокер перевірить ще раз перед встановленням.",
    ),
    "chooseWasm": MessageLookupByLibrary.simpleMessage(
      "Оберіть компонент .wasm",
    ),
    "chooseZip": MessageLookupByLibrary.simpleMessage("Оберіть пакет .zip"),
    "colCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "colFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "colLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "colLinkDevice": MessageLookupByLibrary.simpleMessage("Лінк · пристрій"),
    "colMode": MessageLookupByLibrary.simpleMessage("Режим"),
    "colPoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "colQuality": MessageLookupByLibrary.simpleMessage("Якість"),
    "colRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "colState": MessageLookupByLibrary.simpleMessage("Стан"),
    "colTime": MessageLookupByLibrary.simpleMessage("Час"),
    "colType": MessageLookupByLibrary.simpleMessage("Тип"),
    "colValue": MessageLookupByLibrary.simpleMessage("Значення"),
    "colVersionSource": MessageLookupByLibrary.simpleMessage(
      "Версія · джерело",
    ),
    "colWho": MessageLookupByLibrary.simpleMessage("Хто"),
    "colWhyHere": MessageLookupByLibrary.simpleMessage("Чому тут"),
    "colWrite": MessageLookupByLibrary.simpleMessage("Запис"),
    "configAllowed": MessageLookupByLibrary.simpleMessage(
      "config дозволено для цього верхнього",
    ),
    "configureStaged": MessageLookupByLibrary.simpleMessage(
      "Налаштування · підготовлено",
    ),
    "configureStagedNote": MessageLookupByLibrary.simpleMessage(
      "Готуються разом з іншими змінами; застосовуються в перегляді.",
    ),
    "continueLabel": MessageLookupByLibrary.simpleMessage("Далі"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Не вдалося підключитися до інтернету.",
    ),
    "customPackage": MessageLookupByLibrary.simpleMessage("Власний пакет"),
    "customPackageNote": MessageLookupByLibrary.simpleMessage(
      "Архів пакета, який ви приносите: zip, URL, Git-репозиторій або один .wasm. Перевіряється перед встановленням.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Темна тема"),
    "deauthorizeTitle": m6,
    "decideInSites": MessageLookupByLibrary.simpleMessage("вирішіть у Сайтах"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Галерея дизайну"),
    "discard": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "doneOnTheDevice": m7,
    "doneOnTheDeviceUpgrade": MessageLookupByLibrary.simpleMessage(
      "Хто керує пристроєм, той і оновлює його; він перепідключиться з тим самим сертифікатом.",
    ),
    "downstream": MessageLookupByLibrary.simpleMessage("нижче"),
    "downstreamBrokerQuic": MessageLookupByLibrary.simpleMessage(
      "брокер нижче · через quic",
    ),
    "editParamsNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» застосовується з іншими змінами; лінк перезапуститься з новою ревізією.",
    ),
    "editParamsOf": m8,
    "factBranch": MessageLookupByLibrary.simpleMessage("Гілка"),
    "factCanDo": MessageLookupByLibrary.simpleMessage("Може"),
    "factCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "factDevice": MessageLookupByLibrary.simpleMessage("Пристрій"),
    "factFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "factHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "factKey": MessageLookupByLibrary.simpleMessage("Ключ"),
    "factKind": MessageLookupByLibrary.simpleMessage("Тип"),
    "factRelays": MessageLookupByLibrary.simpleMessage("Ретранслює"),
    "factRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "factSeen": MessageLookupByLibrary.simpleMessage("Побачено"),
    "factVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "failed": MessageLookupByLibrary.simpleMessage("не пройшов"),
    "firstSeen": m9,
    "fromAddress": m10,
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "З офіційного списку",
    ),
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("URL gateway"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445 або кілька через кому",
    ),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git-репозиторій (HTTPS)",
    ),
    "goTo": m11,
    "grantFor": m12,
    "grantLevel": MessageLookupByLibrary.simpleMessage("Рівень"),
    "grantPath": MessageLookupByLibrary.simpleMessage("Ключ або шаблон"),
    "groupChange": MessageLookupByLibrary.simpleMessage("Змінити"),
    "groupOnTheDevice": MessageLookupByLibrary.simpleMessage(
      "Робиться на пристрої, не тут",
    ),
    "groupRemove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "groupRun": MessageLookupByLibrary.simpleMessage("Робота"),
    "groupVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "groupYouControl": MessageLookupByLibrary.simpleMessage(
      "Що ви контролюєте тут",
    ),
    "historyOf": m13,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Тримати невідомі з’єднання тут",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнено (і «Допускати всі» вимкнено): невідомі сертифікати ігноруються.",
    ),
    "howItRunsThere": MessageLookupByLibrary.simpleMessage("Як він там працює"),
    "install": MessageLookupByLibrary.simpleMessage("Встановити"),
    "installRailNote": MessageLookupByLibrary.simpleMessage(
      "Встановлення потребує config на sys (роль admin). Нічого не встановлюється, доки ви не натиснете «Встановити».",
    ),
    "installedOn": m14,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Це не URL gateway (http:// або https:// і хост)",
    ),
    "letItIn": MessageLookupByLibrary.simpleMessage("Допустити"),
    "letTheBrokerIn": MessageLookupByLibrary.simpleMessage("Допустити брокер"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Світла тема"),
    "linkName": MessageLookupByLibrary.simpleMessage("Назва лінка"),
    "linkOverTls": MessageLookupByLibrary.simpleMessage("лінк · через tls"),
    "linksAlready": m15,
    "linksLocalNote": m16,
    "linksOn": m17,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "З’єднання із сертифікатом цього сайту, для яких немає лінка. Вони нічого не читають і не пишуть, доки ви їх не схвалите.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "Вони працюють на своїх машинах і під’єднуються із сертифікатом цього сайту. Ви вирішуєте, що їм доступно і чи лишаються вони; сам пристрій оновлюють там, де він працює.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Лінками на цьому брокері ви керуєте повністю. Лінки на інших пристроях ви лише допускаєте, обмежуєте або відключаєте.",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Завантаження…"),
    "logEmpty": MessageLookupByLibrary.simpleMessage("Рядків немає."),
    "logIn": MessageLookupByLibrary.simpleMessage("Увійти"),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Увійдіть у gateway WYRM.",
    ),
    "logOf": m18,
    "logOut": MessageLookupByLibrary.simpleMessage("Вийти"),
    "manifest": MessageLookupByLibrary.simpleMessage("Маніфест"),
    "modeEmbedded": MessageLookupByLibrary.simpleMessage("Вбудований"),
    "modeEmbeddedNote": MessageLookupByLibrary.simpleMessage(
      "Усередині брокера: найлегший; зупиняється разом із брокером.",
    ),
    "modeExternal": MessageLookupByLibrary.simpleMessage("Зовнішній"),
    "modeExternalNote": MessageLookupByLibrary.simpleMessage(
      "На іншій машині: під’єднується із сертифікатом цього сайту.",
    ),
    "modeProcess": MessageLookupByLibrary.simpleMessage("Процес"),
    "modeProcessNote": MessageLookupByLibrary.simpleMessage(
      "Окремий процес на цьому хості; брокер стежить і перезапускає.",
    ),
    "modeWasmNote": MessageLookupByLibrary.simpleMessage(
      "Усередині брокера в пісочниці: без файлів, лише дозволена мережа, обмеження пам’яті й часу. Визначається типом пакета.",
    ),
    "more": MessageLookupByLibrary.simpleMessage("Ще"),
    "nameIt": MessageLookupByLibrary.simpleMessage("Дайте лінку назву."),
    "nameRule": MessageLookupByLibrary.simpleMessage(
      "Літери, цифри, . _ - · не зайнята іншим лінком, видаленим лінком або сайтом",
    ),
    "nameTaken": MessageLookupByLibrary.simpleMessage(
      "Ця назва вже є в іншого лінка.",
    ),
    "needsConfigOnSys": MessageLookupByLibrary.simpleMessage(
      "Потрібен config на sys",
    ),
    "needsLevelYouHave": m19,
    "needsLevelYouHaveIt": m20,
    "networkError": MessageLookupByLibrary.simpleMessage(
      "Проблема зі з’єднанням",
    ),
    "newValue": MessageLookupByLibrary.simpleMessage("Нове значення"),
    "noHistory": MessageLookupByLibrary.simpleMessage(
      "Немає записаних значень у цьому проміжку. Точку записує спостереження в sys/history.",
    ),
    "noLocalLinks": MessageLookupByLibrary.simpleMessage(
      "На цьому брокері ще немає лінків. Додайте лінк, щоб під’єднати пристрій.",
    ),
    "noPoints": MessageLookupByLibrary.simpleMessage(
      "Тут немає значень. Відкрийте гілку в дереві.",
    ),
    "noRemoteLinks": MessageLookupByLibrary.simpleMessage(
      "Жоден пристрій не під’єднаний як зовнішній лінк.",
    ),
    "noRevisions": MessageLookupByLibrary.simpleMessage("Ревізій немає."),
    "noValue": MessageLookupByLibrary.simpleMessage("немає значення"),
    "noneAsked": MessageLookupByLibrary.simpleMessage("не запитано"),
    "notInstalled": MessageLookupByLibrary.simpleMessage(
      "Брокер не встановив його.",
    ),
    "notRecorded": MessageLookupByLibrary.simpleMessage("не записується"),
    "notWritable": MessageLookupByLibrary.simpleMessage(
      "Лише читання: драйвер не приймає тут значення.",
    ),
    "nothingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "У карантині нічого не чекає.",
    ),
    "nothingStaged": MessageLookupByLibrary.simpleMessage(
      "Нічого не підготовлено. Змініть значення або параметр.",
    ),
    "now": MessageLookupByLibrary.simpleMessage("зараз"),
    "officialList": MessageLookupByLibrary.simpleMessage("Офіційний список"),
    "officialListNote": MessageLookupByLibrary.simpleMessage(
      "Драйвери у wyrmd і пакети з вашого репозиторію. Оберіть, де працюватиме, і встановіть.",
    ),
    "offline": MessageLookupByLibrary.simpleMessage(
      "З’єднання з gateway втрачено. Перепідключення; на екрані останні отримані значення.",
    ),
    "ok": MessageLookupByLibrary.simpleMessage("OK"),
    "onOtherDevices": MessageLookupByLibrary.simpleMessage(
      "На інших пристроях",
    ),
    "onThisBroker": MessageLookupByLibrary.simpleMessage("На цьому брокері"),
    "onWhichBroker": MessageLookupByLibrary.simpleMessage("На якому брокері"),
    "openInExplorer": MessageLookupByLibrary.simpleMessage("Відкрити в дереві"),
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Керування · виконується одразу",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Виконується на пристрої з вашими правами і записується в аудит.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("пакет"),
    "packageNamed": m21,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Пакет із вашого репозиторію · SHA-256 звіряється з індексом під час завантаження",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("URL пакета (HTTPS)"),
    "paramCount": m22,
    "paramsJson": m23,
    "paramsNote": MessageLookupByLibrary.simpleMessage(
      "~meta вузла, як його оголошує брокер: профіль, cfg і attr.",
    ),
    "passed": MessageLookupByLibrary.simpleMessage("пройшов"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "pickOne": MessageLookupByLibrary.simpleMessage("Оберіть лінк зі списку."),
    "pleaseCheckYourNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Перевірте налаштування мережі.",
    ),
    "pleaseLogInAgain": MessageLookupByLibrary.simpleMessage(
      "Увійдіть ще раз.",
    ),
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Значення оновлюються наживо. Зміни готуються в цій сесії; нічого не записується до застосування.",
    ),
    "qCheckFailed": MessageLookupByLibrary.simpleMessage(
      "Пакет не пройшов перевірку",
    ),
    "qCheckOk": MessageLookupByLibrary.simpleMessage(
      "Пакет виглядає правильно",
    ),
    "qChoose": MessageLookupByLibrary.simpleMessage("Що ви хочете додати?"),
    "qFailed": MessageLookupByLibrary.simpleMessage("Брокер не встановив його"),
    "qInstalled": m24,
    "qInstalling": m25,
    "qRun": MessageLookupByLibrary.simpleMessage(
      "Де він працюватиме і під якою назвою?",
    ),
    "quarantine": MessageLookupByLibrary.simpleMessage("Карантин"),
    "recorded": MessageLookupByLibrary.simpleMessage("записується"),
    "refresh": MessageLookupByLibrary.simpleMessage("Оновити"),
    "reject": MessageLookupByLibrary.simpleMessage("Відхилити"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "Цей сертифікат надалі відхилятиметься.",
    ),
    "rejectTitle": m26,
    "remoteFooter": MessageLookupByLibrary.simpleMessage(
      "Якщо пристрій втрачено або вкрадено: «Видалити назавжди». Відкликання — це пауза: схваліть знову з карантину, і він збереже ім’я та дерево.",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "removeDeletesTree": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено. Ім’я можна використати знову.",
    ),
    "removeLinkTitle": m27,
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено, а id вилучено: його не можна використати знову.",
    ),
    "requiredField": MessageLookupByLibrary.simpleMessage("Обов’язкове поле"),
    "resultOf": m28,
    "returns": m29,
    "review": MessageLookupByLibrary.simpleMessage("Перегляд"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage(
      "Переглянути й застосувати",
    ),
    "revision": m30,
    "revisionNow": m31,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Без цього брокер нічого не встановить. Доступи змінюються пізніше через «Надати доступ», інше — параметрами лінка.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "Пакет просить такі права",
    ),
    "rollBack": MessageLookupByLibrary.simpleMessage("Повернути"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Ці параметри стануть новою ревізією, і лінк перезапуститься з ними.",
    ),
    "rollBackTo": m32,
    "rowsAnswered": m33,
    "runNow": MessageLookupByLibrary.simpleMessage("Виконати"),
    "runNowNote": m34,
    "runsOn": m35,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Працює на іншому пристрої",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Той самий виклик з CLI",
    ),
    "searchHint": MessageLookupByLibrary.simpleMessage(
      "Перейти до вузла, дії або лінка",
    ),
    "searchLinks": MessageLookupByLibrary.simpleMessage("Шукати у списку"),
    "secretName": MessageLookupByLibrary.simpleMessage("Назва"),
    "secretValue": MessageLookupByLibrary.simpleMessage(
      "Значення (порожнє — видалити)",
    ),
    "secretsNote": MessageLookupByLibrary.simpleMessage(
      "Брокер запечатує секрет, і він більше не показується; лінк читає його за назвою.",
    ),
    "selectANode": MessageLookupByLibrary.simpleMessage(
      "Оберіть вузол у дереві.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Сесія завершилася"),
    "setSecret": MessageLookupByLibrary.simpleMessage("Зберегти"),
    "setValue": MessageLookupByLibrary.simpleMessage("Задати значення"),
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Щось пішло не так",
    ),
    "stage": MessageLookupByLibrary.simpleMessage("Підготувати"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» додає дію до перегляду разом з іншими змінами.",
    ),
    "stagedChanges": m36,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Нічого не записується, доки ви не застосуєте. Кожна зміна виконується з вашими правами.",
    ),
    "stateConnected": MessageLookupByLibrary.simpleMessage("Під’єднано"),
    "stateFailed": MessageLookupByLibrary.simpleMessage("Збій"),
    "stateInstalled": MessageLookupByLibrary.simpleMessage("Встановлено"),
    "stateOffline": MessageLookupByLibrary.simpleMessage("Офлайн"),
    "stateStarting": MessageLookupByLibrary.simpleMessage("Запускається"),
    "stateStopped": MessageLookupByLibrary.simpleMessage("Зупинено"),
    "stateStopping": MessageLookupByLibrary.simpleMessage("Зупиняється"),
    "stateWaiting": MessageLookupByLibrary.simpleMessage("Чекає"),
    "stepBring": MessageLookupByLibrary.simpleMessage("Принести"),
    "stepCheck": MessageLookupByLibrary.simpleMessage("Перевірка"),
    "stepChoose": MessageLookupByLibrary.simpleMessage("Вибір"),
    "stepInstall": MessageLookupByLibrary.simpleMessage("Встановлення"),
    "stepOf": m37,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Де працює"),
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio увійшла сюди",
    ),
    "tabActions": MessageLookupByLibrary.simpleMessage("Дії"),
    "tabHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "tabParameters": MessageLookupByLibrary.simpleMessage("Параметри"),
    "tabPoints": MessageLookupByLibrary.simpleMessage("Точки"),
    "tagNeeds": m38,
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("виконується одразу"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("готується"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("цей брокер"),
    "toAccept": MessageLookupByLibrary.simpleMessage("прийняти"),
    "treeNote": MessageLookupByLibrary.simpleMessage(
      "Клацніть правою кнопкою або натисніть і утримуйте вузол, щоб побачити дії. sys/** змінюється в Лінках, Доступі, Сайтах і Системі.",
    ),
    "treeOf": m39,
    "tryAgainLater": MessageLookupByLibrary.simpleMessage("Спробуйте пізніше."),
    "upstream": MessageLookupByLibrary.simpleMessage("вище"),
    "user": MessageLookupByLibrary.simpleMessage("Користувач"),
    "viaSite": m40,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Чекає в карантині",
    ),
    "wasValue": m41,
    "whyBring": MessageLookupByLibrary.simpleMessage(
      "Приносьте власний пакет лише тоді, коли його немає в офіційному списку. Zip, URL або Git-репозиторій зі зібраним пакетом, або один компонент.",
    ),
    "whyBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "whyCheck": MessageLookupByLibrary.simpleMessage(
      "Перед встановленням перевіряються архів і вміст: розмір, шляхи, маніфест і його поля, версія протоколу, для яких хостів є бінарники.",
    ),
    "whyChoose": MessageLookupByLibrary.simpleMessage(
      "Більшість лінків — з офіційного списку: драйвер у wyrmd або пакет із вашого репозиторію. Власний пакет — лише якщо його там немає.",
    ),
    "whyDeauthorized": MessageLookupByLibrary.simpleMessage("Відкликано"),
    "whyFailed": MessageLookupByLibrary.simpleMessage(
      "Брокер відповів success: false. Його повідомлення пояснює чому.",
    ),
    "whyInstalled": MessageLookupByLibrary.simpleMessage(
      "Він працює, має власну ідентичність і оголосив свою гілку.",
    ),
    "whyInstalling": MessageLookupByLibrary.simpleMessage(
      "Це триває кілька секунд. Можна піти — встановлення продовжиться.",
    ),
    "whyNew": MessageLookupByLibrary.simpleMessage("Новий"),
    "whyRunCustom": MessageLookupByLibrary.simpleMessage(
      "Оберіть брокер. Лише брокери, для чийого хоста зібрано пакет, можуть його прийняти; спосіб роботи задає тип пакета.",
    ),
    "whyRunOfficial": MessageLookupByLibrary.simpleMessage(
      "Оберіть брокер, потім як лінк на ньому працюватиме. Вбудований драйвер може працювати в брокері, окремим процесом або на іншій машині.",
    ),
    "wsAccess": MessageLookupByLibrary.simpleMessage("Доступ"),
    "wsAssistant": MessageLookupByLibrary.simpleMessage("Асистент"),
    "wsExplorer": MessageLookupByLibrary.simpleMessage("Дерево"),
    "wsFlows": MessageLookupByLibrary.simpleMessage("Потоки"),
    "wsHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "wsLinks": MessageLookupByLibrary.simpleMessage("Лінки"),
    "wsSites": MessageLookupByLibrary.simpleMessage("Сайти"),
    "wsSystem": MessageLookupByLibrary.simpleMessage("Система"),
    "yourAnswers": MessageLookupByLibrary.simpleMessage("Ваші відповіді"),
    "yourAnswersNote": MessageLookupByLibrary.simpleMessage(
      "Ваші відповіді. Натисніть крок ліворуч, щоб змінити.",
    ),
    "zipFile": MessageLookupByLibrary.simpleMessage("Zip-файл"),
  };
}
