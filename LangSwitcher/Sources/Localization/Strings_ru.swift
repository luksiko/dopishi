import Foundation

// MARK: - Russian Strings (Русский)
// Перевод всех строк интерфейса LangSwitcher на русский язык.

enum Strings_ru {

    static let strings: [String: String] = [

        // ── Меню (StatusBarController) ──────────────────────────────
        "menu.header":                   "⌨ LangSwitcher",
        "menu.convertText":              "Конвертировать текст",
        "menu.switchLayout":             "Переключить раскладку",
        "menu.activeLayouts":            "Активные раскладки:",
        "menu.conversions":              "Конвертаций:",
        "menu.settings":                 "Настройки...",
        "menu.about":                    "О LangSwitcher",
        "menu.quit":                     "Завершить LangSwitcher",
        "menu.tooltip":                  "LangSwitcher — %@ для конвертации",

        // ── Окно настроек ───────────────────────────────────────────
        "settings.windowTitle":          "Настройки LangSwitcher",
        "settings.tab.general":          "Основные",
        "settings.tab.layouts":          "Раскладки",
        "settings.tab.hotkey":           "Горячая клавиша",
        "settings.tab.ai":               "AI Помощник",
        "settings.tab.permissions":      "Разрешения",
        "settings.tab.log":              "Журнал",
        "settings.iconStyle.languageBadge": "Код языка в рамке (RU, EN)",
        "settings.iconStyle.keyboardIcon":  "Значок клавиатуры",

        // ── Вкладка «Основные» ──────────────────────────────────────
        "general.language":              "Язык",
        "general.statusBarIcon":         "Иконка в строке меню",
        "general.launchAtLogin":         "Запускать при входе в систему",
        "general.playSound":             "Звук при конвертации",
        "general.showNotifications":     "Показывать уведомления",
        "general.smartConversion":       "Умная конвертация (без выделения)",
        "general.mode":                  "Режим:",
        "general.layoutSwitch":          "Переключение раскладки по горячей клавише",
        "general.howItWorks":            "Как это работает",
        "general.howItWorksText":        "Если текст выделен, горячая клавиша конвертирует выделение.\nЕсли текст не выделен, поведение зависит от режима умной конвертации выше.",
        "general.statistics":            "Статистика",
        "general.totalConversions":      "Всего конвертаций:",

        // ── Режимы умной конвертации ────────────────────────────────
        "smartMode.lastWord.name":       "Только последнее слово",
        "smartMode.greedyLine.name":     "Жадный (вся фраза)",
        "smartMode.disabled.name":       "Отключено",
        "smartMode.lastWord.desc":       "Конвертирует только последнее набранное слово перед курсором.",
        "smartMode.greedyLine.desc":     "Выделяет текст до начала строки, находит место начала неправильной раскладки и конвертирует всю фразу.",
        "smartMode.disabled.desc":       "Умная конвертация отключена. Необходимо вручную выделить текст перед нажатием горячей клавиши.",

        // ── Режимы переключения раскладки ───────────────────────────
        "layoutSwitchMode.always.name":          "Всегда переключать раскладку",
        "layoutSwitchMode.ifLastWord.name":      "Переключать, если последнее слово было конвертировано",
        "layoutSwitchMode.ifAnyWord.name":       "Переключать, если хоть одно слово потребовало конвертации",
        "layoutSwitchMode.never.name":           "Не переключать раскладку",
        "layoutSwitchMode.always.desc":          "Всегда переключать раскладку клавиатуры при нажатии горячей клавиши, даже если текст не потребовал конвертации.",
        "layoutSwitchMode.ifLastWord.desc":      "Переключать раскладку по горячей клавише, только если последнее слово перед курсором было конвертировано.",
        "layoutSwitchMode.ifAnyWord.desc":       "Переключать раскладку по горячей клавише, если хотя бы одно слово в тексте было конвертировано.",
        "layoutSwitchMode.never.desc":           "Конвертировать текст по горячей клавише без смены раскладки клавиатуры.",

        // ── Вкладка «Раскладки» ─────────────────────────────────────
        "layouts.title":                 "Активные раскладки клавиатуры",
        "layouts.description":           "Эти раскладки определены из настроек системной клавиатуры. Конвертер сопоставляет символы между ними на основе физических позиций клавиш.",
        "layouts.refresh":               "Обновить из системы",
        "layouts.count":                 "Обнаружено раскладок: %d",

        // ── Переключение раскладки одиночной клавишей ───────────────
        "layoutSwitchKey.title":         "Клавиша переключения языка",
        "layoutSwitchKey.description":   "Быстрое переключение системной раскладки одиночной клавишей без конвертации текста.",
        "layoutSwitchKey.current":       "Клавиша переключения:",
        "layoutSwitchKey.disabled":      "Отключено",
        "layoutSwitchKey.capsLock":      "Caps Lock",
        "layoutSwitchKey.rightOption":   "Правый Option (⌥)",
        "layoutSwitchKey.rightCommand":  "Правый Command (⌘)",
        "layoutSwitchKey.rightShift":    "Правый Shift (⇧)",
        "layoutSwitchKey.rightControl":  "Правый Control (⌃)",
        "layoutSwitchKey.leftOption":    "Левый Option (⌥)",
        "layoutSwitchKey.leftControl":   "Левый Control (⌃)",
        "layoutSwitchKey.leftCommand":   "Левый Command (⌘)",
        "layoutSwitchKey.leftShift":     "Левый Shift (⇧)",
        "layoutSwitchKey.fn":            "Fn / Globe (fn)",
        "layoutSwitchKey.hint":          "Нажатие этой клавиши циклически переключает включенные раскладки клавиатуры. Быстро и независимо от конвертации текста.",

        // ── Вкладка «Горячая клавиша» ───────────────────────────────
        "hotkey.title":                  "Сочетание клавиш",
        "hotkey.description":            "Нажмите это сочетание клавиш для конвертации текста. Если текст выделен — конвертируется выделение; иначе автоматически выделяется последнее слово.",
        "hotkey.current":                "Текущее сочетание:",
        "hotkey.useDoubleShift":         "Использовать двойной Shift (⇧⇧)",
        "hotkey.doubleShiftHint":        "Быстро нажмите Shift дважды для конвертации. Рекомендуемое сочетание — быстрое и не конфликтует с другими приложениями.",
        "hotkey.customTitle":            "Пользовательское сочетание",

        // ── Запись горячей клавиши ───────────────────────────────────
        "hotkeyRecorder.prompt":         "Нажмите «Записать» и нажмите нужное сочетание клавиш:",
        "hotkeyRecorder.pressKey":       "Нажмите сочетание клавиш...",
        "hotkeyRecorder.cancel":         "Отмена",
        "hotkeyRecorder.record":         "Записать",

        // ── Вкладка «Разрешения» ────────────────────────────────────
        "permissions.title":             "Разрешения",
        "permissions.description":       "LangSwitcher нуждается в доступе к функциям универсального доступа для чтения и замены выделенного текста в других приложениях.",
        "permissions.accessibilityTitle":"Доступ к универсальному доступу",
        "permissions.granted":           "Предоставлен — LangSwitcher может конвертировать текст",
        "permissions.notGranted":        "Не предоставлен — включите в Системных настройках",
        "permissions.grantAccess":       "Предоставить доступ",
        "permissions.howToEnable":       "Как включить:",
        "permissions.step1":             "1. Откройте Системные настройки > Конфиденциальность > Универсальный доступ",
        "permissions.step2":             "2. Нажмите значок замка для внесения изменений",
        "permissions.step3":             "3. Включите LangSwitcher в списке",
        "permissions.step4":             "4. При необходимости перезапустите LangSwitcher",
        "permissions.openSettings":      "Открыть Системные настройки",
        "permissions.refreshStatus":     "Обновить статус",

        // ── Вкладка «Журнал конвертаций» ────────────────────────────
        "log.title":                     "Журнал конвертаций",
        "log.entries":                   "записей: %d",
        "log.exportJSON":                "Экспорт JSON",
        "log.clearAll":                  "Очистить всё",
        "log.ratingHint":                "Оцените каждую конвертацию как правильную или неправильную для обучающих данных. Нажимайте: без оценки -> правильно -> неправильно -> без оценки.",
        "log.emptyTitle":                "Конвертаций пока нет.",
        "log.emptyHint":                 "Используйте горячую клавишу для конвертации текста, и записи появятся здесь.",
        "log.clearConfirmTitle":         "Очистить весь журнал?",
        "log.clearConfirmMessage":       "Все записи журнала конвертаций будут безвозвратно удалены. Это действие нельзя отменить.",
        "log.cancel":                    "Отмена",
        "log.deleteEntry":               "Удалить эту запись",
        "log.exportPanelTitle":          "Экспорт журнала конвертаций",
        "log.ratingUnrated":             "Без оценки — нажмите, чтобы отметить как правильное",
        "log.ratingCorrect":             "Правильно — нажмите, чтобы отметить как неправильное",
        "log.ratingIncorrect":           "Неправильно — нажмите, чтобы сбросить оценку",

        // ── Настройки журналирования (вкладка «Основные») ───────────
        "general.logging":               "Журнал конвертаций",
        "general.loggingEnabled":        "Включить журнал конвертаций",
        "general.loggingDisabledNote":   "Журнал отключён по умолчанию для вашей конфиденциальности. При включении конвертации сохраняются локально на вашем Mac.",
        "general.logMaxEntries":         "Максимум записей в журнале",
        "general.logUnlimited":          "0 = без ограничений",

        // ── Журнал отключён (вкладка «Журнал») ─────────────────────
        "log.unlimited":                 "Безлимитно",
        "log.disabledTitle":             "Журнал отключён",
        "log.disabledHint":              "Включите журнал выше, чтобы начать запись конвертаций.",

        // ── Окно «О программе» ──────────────────────────────────────
        "about.windowTitle":             "О программе LangSwitcher",
        "about.appName":                 "LangSwitcher",
        "about.version":                 "Версия 1.3.0",
        "about.tagline":                 "Конвертер раскладки клавиатуры для macOS с открытым кодом",
        "about.howToUse":                "Как использовать:",
        "about.step1":                   "Выделите текст, набранный не в той раскладке",
        "about.step2":                   "Нажмите ⇧⇧ (двойной Shift)",
        "about.step3":                   "Текст автоматически конвертируется!",
        "about.github":                  "GitHub",
        "about.license":                 "Лицензия MIT",

        // ── Алерты (AppDelegate) ────────────────────────────────────
        "alert.accessibilityTitle":      "Требуется доступ к универсальному доступу",
        "alert.accessibilityMessage":    """
LangSwitcher нуждается в разрешении универсального доступа для чтения и замены текста.

Откройте Системные настройки → Конфиденциальность → Универсальный доступ и включите LangSwitcher.

При запуске из Xcode: добавьте собранное приложение из DerivedData или сам Xcode.

Если разрешение уже предоставлено, но не работает:
1. Удалите LangSwitcher из списка универсального доступа
2. Добавьте заново
3. Перезапустите приложение

Также проверьте: Конфиденциальность → Мониторинг ввода — LangSwitcher может быть нужен и там.
""",
        "alert.openSystemSettings":      "Открыть Системные настройки",
        "alert.continueAnyway":          "Продолжить",

        // ── Общее ───────────────────────────────────────────────────
        "common.cancel":                 "Отмена",
        "common.ms":                     "мс",

        "menu.previewRecovery":          "Предпросмотр восстановления...",
        "general.autoCorrectOnSpace":      "Автокоррекция по пробелу",
        "general.autoCorrectOnSpaceHint":  "Автоматически конвертировать последнее слово при нажатии пробела, если оно выглядит набранным в другой раскладке.",
        "general.thoughtRecovery":         "Восстановление текста",
        "general.thoughtRecoveryEnabled":  "Восстанавливать смешанные предложения",
        "general.thoughtRecoveryPreview":  "Показывать предпросмотр перед применением",
        "general.thoughtRecoveryHint":     "Исправляет только слова, сломанные раскладкой, внутри предложений со смешанными языками — код, ссылки и намеренные английские слова не трогаются. Выбор «оставить как есть» в предпросмотре учит личный словарь.",
        "general.recoveryStats":           "Восстановлений:",
        "general.recoveryRevertRate":      "отменено",
        "hotkey.doubleShiftMode":        "Двойной Shift (⇧⇧)",
        "hotkey.doubleOptionMode":       "Двойной Option (⌥⌥)",
        "hotkey.customMode":             "Пользовательское сочетание",
        "hotkey.doubleOptionHint":       "Быстро нажмите Option дважды для конвертации. Сочетания Option+клавиша (⌥+клавиша) игнорируются и не вызывают конвертацию.",
        "permissions.inputMonitoringTitle":   "Мониторинг ввода",
        "permissions.inputMonitoringGranted": "Предоставлен — горячие клавиши работают по всей системе",
        "permissions.inputMonitoringNotGranted": "Не предоставлен — горячие клавиши могут не срабатывать в других приложениях",
        "permissions.crossAppTitle":     "Текущее приложение",
        "permissions.crossAppFrontmost": "Активное приложение:",
        "permissions.crossAppFull":      "Конвертация в этом приложении должна работать",
        "permissions.crossAppLimited":   "В этом приложении (например, терминале) конвертация может работать ограниченно — проверяйте результат",
        "recovery.title":                "Восстановление текста",
        "recovery.subtitle":             "Изменятся только выделенные слова.",
        "recovery.nothingToChange":      "В этой строке нечего восстанавливать — она уже читается как язык.",
        "recovery.original":             "Набрано",
        "recovery.reconstructed":        "Восстановлено",
        "recovery.alternatives":         "Другие варианты",
        "recovery.changedSpans":         "Изменённые слова",
        "recovery.confidence":           "Уверенность: %@",
        "recovery.apply":                "Применить",
        "recovery.copy":                 "Копировать",
        "recovery.revert":               "Оставить как есть",
        "recovery.revertHint":           "Вариант «оставить как есть» также запоминает эти слова — больше они не будут исправляться.",
        "recovery.kind.wrongLayout":     "раскладка",
        "recovery.kind.intentionalForeign": "другое слово",
        "recovery.kind.code":            "код",
        "recovery.kind.url":             "ссылка",
        "recovery.kind.properName":      "имя",
        "recovery.kind.ambiguous":       "неясно",
        "recovery.kind.correct":         "верно",
        "recovery.kind.separator":       "разделитель",

        "notification.layoutSwitched":   "Раскладка: %@",

        // ── Автоисправление ────────────────────────────────────────
        "general.autoCorrection":                "Автоисправление",
        "general.autoCorrectionEnabled":         "Автоисправление раскладки при пробеле/Enter",
        "general.autoCorrectionDesc":            "Автоматически обнаруживает и исправляет слова, набранные в неправильной раскладке, при нажатии пробела, Enter или знака пунктуации. Использует системную проверку правописания для уменьшения ложных срабатываний.",
        "general.autoCorrectionSpellCheck":      "Проверять системным словарём",
        "general.autoCorrectionSpellCheckDesc":  "Автоисправление только когда преобразованное слово распознаётся проверкой правописания macOS. Уменьшает ложные срабатывания, но может пропускать некоторые слова.",
        "general.autoCorrectionSwitchLayout":    "Переключать язык ввода после автоисправления",
        "general.autoCorrectionSwitchLayoutDesc": "Автоматически переключать раскладку/язык клавиатуры в macOS на язык исправленного слова (например, на русский после «ghbdtn » → «привет »).",

        // ── Автодополнение ──────────────────────────────────────────
        "general.autocompletion":                "Автодополнение слов",
        "autocompletion.enabled":                "Показывать подсказки слов при наборе",
        "autocompletion.desc":                   "Показывает всплывающие варианты слов возле курсора при вводе. Подсказывает слова как в текущей, так и в парной раскладке.",
        "autocompletion.acceptKey":              "Клавиша вставки слова",
        "autocompletion.acceptKey.tab":          "Tab (⇥)",
        "autocompletion.acceptKey.space":        "Пробел (␣)",
        "autocompletion.acceptKey.enter":        "Enter (↩)",
        "autocompletion.acceptKey.rightArrow":   "Стрелка вправо (→)",
        "autocompletion.acceptKey.custom":       "Своя клавиша",
        "autocompletion.acceptAllKey":           "Клавиша вставки всей фразы",
        "autocompletion.acceptAllKey.shiftTab":   "Shift + Tab (⇧⇥)",
        "autocompletion.acceptAllKey.cmdReturn":  "Cmd + Enter (⌘↩)",
        "autocompletion.acceptAllKey.optionTab":  "Option + Tab (⌥⇥)",
        "autocompletion.acceptAllKey.custom":    "Своя клавиша",
        "autocompletion.customKey":              "Своя клавиша:",
        "autocompletion.recordKey":              "Нажмите клавишу...",
        "autocompletion.changeKey":              "Изменить",
        "autocompletion.useNumberShortcuts":     "Выбор цифрами (1–5)",
        "autocompletion.includeCrossLayout":     "Подсказывать слова из другой раскладки",
        "autocompletion.crossLayoutDesc":        "Например, при наборе 'ghbd' подскажет 'привет' и автоматически переключит раскладку.",
        "autocompletion.suggestProfanity":       "Предлагать нецензурные слова",
        "autocompletion.suggestProfanityDesc":   "Разрешить ненормативную лексику и мат в подсказках автодополнения. По умолчанию отключено.",
        "autocompletion.maxSuggestions":         "Количество подсказок:",
        "autocompletion.minPrefixLength":        "Минимум символов для подсказки:",
        "autocompletion.delay":                  "Задержка появления подсказок:",
        "autocompletion.delayDesc":              "Пауза перед отображением всплывающего окна подсказок.",
        "autocompletion.hint.toAccept":          "вставить",
        "autocompletion.displayMode":            "Стиль отображения",
        "autocompletion.displayMode.popup":      "Всплывающее меню",
        "autocompletion.displayMode.ghostText":  "Полупрозрачный хвост (Ghost Text)",
        "autocompletion.displayMode.both":       "Оба варианта (Меню + Ghost Text)",
        "autocompletion.displayModeDesc.popup":     "Показывает список вариантов под курсором ввода.",
        "autocompletion.displayModeDesc.ghostText": "Отображает ненавязчивое продолжение слова прямо в строке за курсором.",
        "autocompletion.displayModeDesc.both":      "Отображает продолжение в строке и меню дополнительных вариантов.",
        "autocompletion.resetAdaptive":          "Сбросить историю адаптивного обучения",
        "autocompletion.adaptiveResetDone":      "История обучения сброшена.",

        // ── Excluded Apps ────────────────────────────────────────────
        "excludedApps.title":                    "Исключённые приложения",
        "excludedApps.desc":                     "Автоисправление и автодополнение будут отключены в этих программах.",
        "excludedApps.empty":                    "Нет исключённых приложений. Добавьте программы, в которых помощники не нужны.",
        "excludedApps.addRunning":               "Добавить запущенное приложение...",
        "excludedApps.chooseFromDisk":           "Выбрать с диска...",
        "permissions.serviceTitle": "Служба автоисправления",
        "permissions.service.disabled": "Отключена в настройках",
        "permissions.service.permissionRequired": "Требуется доступ Accessibility",
        "permissions.service.running": "Перехват клавиш активен",
        "permissions.service.failed": "Не удалось запустить перехват; повторяем автоматически",
        "permissions.serviceDetail": "Проверяем разрешение и перехват каждые 5 секунд и после пробуждения. Активный перехват не означает исправление каждого слова.",
        "permissions.restartService": "Перезапустить службу",
        "permissions.copiesTitle": "Копии приложения",
        "permissions.copiesDetail": "Ниже — копии, известные macOS. Одновременно может работать одна копия на пользователя. Статус Accessibility относится к текущей копии; доступ других копий здесь проверить нельзя. Храните установленное приложение в /Applications, ненужные копии удаляйте через Finder.",
        "permissions.currentCopy": "Текущая копия",
        "permissions.otherCopy": "Другая копия",
        "permissions.revealCopy": "Показать в Finder",
        "permissions.instanceError": "Не удалось защититься от повторного запуска",
        "permissions.instanceErrorDetail": "LangSwitcher завершится, чтобы не запускать несколько обработчиков клавиш. Проверьте доступ к папке приложения в Application Support.",

        // ── AI Assistant ─────────────────────────────────────────────
        "ai.title":                              "Локальный AI Помощник",
        "ai.subtitle":                           "Локальная нейросеть для предиктивного набора (100% офлайн, без интернета).",
        "ai.model.name":                         "Модель",
        "ai.model.status":                       "Статус",
        "ai.model.status.ready":                 "Готов к работе",
        "ai.model.status.downloading":           "Загрузка (%@)",
        "ai.model.status.notDownloaded":         "Не загружен",
        "ai.model.status.error":                 "Ошибка",
        "ai.model.downloadButton":               "Загрузить модель (~390 МБ)",
        "ai.model.cancelDownload":               "Отмена",
        "ai.model.deleteButton":                 "Удалить модель",
        "ai.model.deleteConfirm":                "Вы уверены, что хотите удалить веса модели?",
        "ai.predictive.enable":                  "Предиктивное продолжение текста",
        "ai.predictive.desc":                    "Предлагает продолжение на 2–4 слова при паузе в наборе (350 мс).",
        "ai.predictive.wordCount":               "Длина продолжения",
        "ai.predictive.words":                   "%d слова",
        "ai.predictive.debounceDelay":           "Задержка подсказок:",
        "ai.predictive.debounceDesc":            "Пауза в наборе текста перед появлением подсказок AI.",
        "ai.predictive.fast":                    "150 мс (Быстро)",
        "ai.predictive.slow":                    "1000 мс (Спокойно)",
        "ai.battery.title":                      "Режим батареи",
        "ai.battery.desc":                       "Автоматически отключать фоновый AI при работе от аккумулятора (остаётся только мгновенный словарный режим).",
        "ai.battery.status.ac":                  "⚡ Питание от сети — AI активен",
        "ai.battery.status.battery":             "🔋 Работа от аккумулятора — AI приостановлен для экономии",
        "ai.battery.status.unknown":             "Источник питания: %@",

        // ── Recommended Models ─────────────────────────────────────────
        "ai.model.recommended":                  "Рекомендуемые модели",
        "ai.model.recommended.desc":             "Выберите локальную модель для быстрых подсказок без отправки данных в облако.",
        "ai.model.active":                       "Активна",
        "ai.model.select":                       "Выбрать",
        "ai.model.badge.recommended":            "Рекомендуется",
        "ai.model.desc.qwen05b":                 "Сверхбыстрая Qwen 0.5B, идеальный баланс скорости и качества на любом Mac.",
        "ai.model.desc.smollm360m":               "Минималистичная модель 360M с минимальным потреблением памяти (~229 МБ).",
        "ai.model.desc.qwen15b":                 "Высокое качество продолжений и словарный запас, для Mac с 16+ ГБ RAM.",
        "ai.model.desc.llama1b":                 "Компактная модель Meta Llama 3.2, оптимизированная для естественной речи.",

        // ── AI Custom Instructions ─────────────────────────────────────
        "ai.instructions.title":                 "Инструкции для AI",
        "ai.instructions.desc":                  "Персонализируйте стиль продолжений, роль или правила для терминов.",
        "ai.instructions.placeholder":           "Например: Я программист, пиши лаконично, термины оставляй на английском.",
        "ai.instructions.preset.coder":          "Программист",
        "ai.instructions.preset.coder.text":     "Я программист, пиши лаконично, термины оставляй на английском.",
        "ai.instructions.preset.concise":        "Лаконично",
        "ai.instructions.preset.concise.text":   "Пиши кратко и по существу, без лишних вводных слов.",
        "ai.instructions.preset.business":       "Деловой стиль",
        "ai.instructions.preset.business.text":  "Вежливый и профессиональный деловой стиль общения.",
        "ai.instructions.clear":                 "Очистить",

        // ── Extended Statistics ───────────────────────────────────────
        "ai.stats.title":                        "Статистика продуктивности",
        "ai.stats.savedChars":                   "Сэкономлено символов",
        "ai.stats.savedClicks":                  "Сэкономлено кликов/клавиш",
        "ai.stats.conversions":                  "Исправлений",
        "ai.stats.reset":                        "Сбросить статистику",
        "ai.stats.resetConfirm":                 "Вы уверены, что хотите сбросить всю накопленную статистику?",
    ]

    @MainActor static func register() {
        LocalizationManager.shared.register(language: "ru", strings: strings)
    }
}
