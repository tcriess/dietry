// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Dietry';

  @override
  String get overviewTitle => 'Resumen';

  @override
  String get addFoodTitle => 'Añadir alimento';

  @override
  String get nutrientCalories => 'Calorías';

  @override
  String get nutrientProtein => 'Proteína';

  @override
  String get nutrientFat => 'Grasa';

  @override
  String get nutrientCarbs => 'Carbohidratos';

  @override
  String get nutrientFiber => 'Fibra';

  @override
  String get nutrientSugar => 'Azúcar';

  @override
  String get nutrientSalt => 'Sal';

  @override
  String get nutrientSaturatedFat => 'Grasas saturadas';

  @override
  String get ofWhichCarbs => 'de los cuales azúcares';

  @override
  String get ofWhichFat => 'de los cuales saturadas';

  @override
  String get goal => 'Meta';

  @override
  String get consumed => 'Consumido';

  @override
  String get remaining => 'Restante';

  @override
  String get today => 'Hoy';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get saving => 'Guardando...';

  @override
  String get delete => 'Eliminar';

  @override
  String get edit => 'Editar';

  @override
  String get add => 'Agregar';

  @override
  String get requiredField => 'Requerido';

  @override
  String errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get previousDay => 'Día Anterior';

  @override
  String get nextDay => 'Día Siguiente';

  @override
  String get loading => 'Cargando...';

  @override
  String get navOverview => 'Resumen';

  @override
  String get navEntries => 'Entradas';

  @override
  String get navActivities => 'Actividades';

  @override
  String get navReports => 'Informes';

  @override
  String get mealBreakfast => 'Desayuno';

  @override
  String get mealLunch => 'Almuerzo';

  @override
  String get mealDinner => 'Cena';

  @override
  String get mealSnack => 'Refrigerio';

  @override
  String get genderMale => 'Masculino';

  @override
  String get genderFemale => 'Femenino';

  @override
  String get activityLevelSedentary => 'Sedentario (Trabajo de oficina)';

  @override
  String get activityLevelLight => 'Ligero (1-3x/semana ejercicio)';

  @override
  String get activityLevelModerate => 'Moderado (3-5x/semana ejercicio)';

  @override
  String get activityLevelActive => 'Activo (6-7x/semana ejercicio)';

  @override
  String get activityLevelVeryActive => 'Muy activo (entrenamiento 2x diario)';

  @override
  String get weightGoalLose => 'Perder Peso (0.5 kg/semana)';

  @override
  String get weightGoalMaintain => 'Mantener Peso';

  @override
  String get weightGoalGain => 'Aumentar Peso (Construir músculo)';

  @override
  String get caloriesBurned => 'Quemado';

  @override
  String get netCalories => 'Neto';

  @override
  String get date => 'Fecha';

  @override
  String get noGoalTitle => 'Sin Objetivo Nutricional';

  @override
  String get noGoalMessage =>
      'Crea tu primer objetivo nutricional para seguir tu progreso.';

  @override
  String get createGoal => 'Crear Objetivo Nutricional';

  @override
  String get entriesTitle => 'Entradas';

  @override
  String get entriesEmpty => 'Sin entradas';

  @override
  String get entriesEmptyHint => '¡Agrega tu primera comida!';

  @override
  String get deleteEntryTitle => '¿Eliminar Entrada?';

  @override
  String deleteEntryConfirm(String name) {
    return '¿Realmente quieres eliminar \"$name\"?';
  }

  @override
  String get entryDeleted => 'Entrada eliminada';

  @override
  String get myFoods => 'Mis Alimentos';

  @override
  String get addEntry => 'Agregar Entrada';

  @override
  String get activitiesTitle => 'Actividades';

  @override
  String get activitiesEmpty => 'Sin Actividades';

  @override
  String get activitiesEmptyHint => '¡Agrega tu primera actividad!';

  @override
  String get deleteActivityTitle => '¿Eliminar Actividad?';

  @override
  String deleteActivityConfirm(String name) {
    return '¿Realmente quieres eliminar \"$name\"?';
  }

  @override
  String get activityDeleted => 'Actividad eliminada';

  @override
  String get addActivity => 'Agregar Actividad';

  @override
  String get myActivities => 'Mis Actividades';

  @override
  String get importHealthConnect => 'Importar de Health Connect';

  @override
  String get healthConnectImporting => 'Importando actividades...';

  @override
  String get healthConnectNoResults => 'No se encontraron nuevas actividades';

  @override
  String healthConnectSuccess(int count) {
    return '$count actividades importadas';
  }

  @override
  String healthConnectError(String error) {
    return 'Error en la importación: $error';
  }

  @override
  String get healthConnectUnavailable =>
      'Health Connect no disponible en este dispositivo';

  @override
  String healthConnectSuccessBody(int count) {
    return '$count mediciones importadas';
  }

  @override
  String get importRangeTitle => 'Período de importación';

  @override
  String importRangeSinceGoal(String date) {
    return 'Desde el inicio del seguimiento ($date)';
  }

  @override
  String get importRangeAll => 'Todos los datos disponibles';

  @override
  String get addFoodScreenTitle => 'Agregar Alimento';

  @override
  String get searchHint => 'p.ej., Manzana, Arroz, Pollo...';

  @override
  String get onlineSearch => 'Búsqueda en Línea';

  @override
  String get myDatabase => 'Mi Base de Datos';

  @override
  String get amount => 'Cantidad';

  @override
  String get unit => 'Unidad';

  @override
  String get mealType => 'Comida';

  @override
  String get manualEntry => 'Manual';

  @override
  String get useFood => 'Usar';

  @override
  String get saveToDatabase => 'Agregar a la Base de Datos';

  @override
  String get entrySaved => '¡Entrada guardada!';

  @override
  String get searchEnterHint => 'Presiona Enter para buscar';

  @override
  String get caloriesLabel => 'Calorías';

  @override
  String get proteinLabel => 'Proteína';

  @override
  String get fatLabel => 'Grasa';

  @override
  String get carbsLabel => 'Carbohidratos';

  @override
  String get foodDatabaseTitle => 'Mis Alimentos';

  @override
  String foodAdded(String name) {
    return '\"$name\" agregado';
  }

  @override
  String foodUpdated(String name) {
    return '\"$name\" actualizado';
  }

  @override
  String get foodDeleted => 'Eliminado';

  @override
  String get deleteFoodTitle => '¿Eliminar Alimento?';

  @override
  String deleteFoodConfirm(String name) {
    return '\"$name\" se eliminará permanentemente. Las entradas existentes se conservan.';
  }

  @override
  String get foodName => 'Nombre';

  @override
  String get foodCaloriesPer100 => 'Calorías (kcal/100g)';

  @override
  String get foodProteinPer100 => 'Proteína (g/100g)';

  @override
  String get foodFatPer100 => 'Grasa (g/100g)';

  @override
  String get foodCarbsPer100 => 'Carbohidratos (g/100g)';

  @override
  String get foodCategory => 'Categoría (opcional)';

  @override
  String get foodBrand => 'Marca (opcional)';

  @override
  String get foodPortionsTitle => 'Tamaños de Porción';

  @override
  String get foodPortionsEmpty =>
      'Sin porciones definidas – siempre ingresa en g/ml';

  @override
  String get foodPublic => 'Visible para todos los usuarios';

  @override
  String get foodPublicOn => 'Todos pueden encontrar este alimento';

  @override
  String get foodPublicOff => 'Solo tú ves esta entrada';

  @override
  String get foodIsLiquid => 'Alimento líquido';

  @override
  String get foodIsLiquidHint =>
      'La cantidad cuenta para la ingesta diaria de agua';

  @override
  String get newFood => 'Nuevo Alimento';

  @override
  String get nutritionPer100 => 'Valores nutricionales por 100g';

  @override
  String get statusPublic => 'Público';

  @override
  String get statusPending => 'Pendiente';

  @override
  String get editEntryTitle => 'Editar Entrada';

  @override
  String get entryUpdated => '¡Cambios guardados!';

  @override
  String get profileTitle => 'Perfil';

  @override
  String get profileDataTitle => 'Datos de Perfil';

  @override
  String get profileDataEmpty => 'Perfil aún no configurado';

  @override
  String get setupProfile => 'Configurar Perfil';

  @override
  String get editProfile => 'Editar Perfil';

  @override
  String get goalCardTitle => 'Objetivo Nutricional';

  @override
  String get goalEmpty => 'Sin objetivo nutricional';

  @override
  String get createGoalButton => 'Crear Objetivo';

  @override
  String get adjustGoal => 'Ajustar Objetivo';

  @override
  String get measurementTitle => 'Medida Actual';

  @override
  String get measurementEmpty => 'Sin medida registrada';

  @override
  String get addWeight => 'Ingresar Peso';

  @override
  String get weight => 'Peso';

  @override
  String get height => 'Altura';

  @override
  String get birthdate => 'Fecha de Nacimiento';

  @override
  String ageYears(int age) {
    return '$age años';
  }

  @override
  String get gender => 'Género';

  @override
  String get activityLevelLabel => 'Nivel de Actividad';

  @override
  String get weightGoalLabel => 'Objetivo de Peso';

  @override
  String get bodyFat => 'Grasa Corporal';

  @override
  String get muscleMass => 'Masa Muscular';

  @override
  String get waist => 'Circunferencia de Cintura';

  @override
  String get weightProgress => 'Progreso de Peso';

  @override
  String get rangeMonth1 => '1 Mes';

  @override
  String get rangeMonths3 => '3 Meses';

  @override
  String get rangeMonths6 => '6 Meses';

  @override
  String get rangeYear1 => '1 Año';

  @override
  String get rangeAll => 'Todo';

  @override
  String get deleteMeasurementTitle => '¿Eliminar Medida?';

  @override
  String deleteMeasurementConfirm(String date) {
    return '¿Eliminar medida del $date?';
  }

  @override
  String get measurementDeleted => 'Medida eliminada';

  @override
  String get profileInfoText =>
      'Tus datos se utilizan para recomendaciones personalizadas.';

  @override
  String measurementsSection(int count) {
    return 'Medidas ($count)';
  }

  @override
  String get latestBadge => 'Actual';

  @override
  String get profileSetupTitle => 'Configurar Perfil';

  @override
  String get profileEditTitle => 'Editar Perfil';

  @override
  String get birthdateRequired => 'Por favor selecciona fecha de nacimiento';

  @override
  String get heightLabel => 'Altura *';

  @override
  String get heightInvalid => 'Altura inválida (100-250cm)';

  @override
  String get genderLabel => 'Género';

  @override
  String get activityLevelFieldLabel => 'Nivel de Actividad';

  @override
  String get weightGoalFieldLabel => 'Objetivo de Peso';

  @override
  String get profileSaved => '¡Perfil guardado!';

  @override
  String get addMeasurementTitle => 'Ingresar Medida';

  @override
  String get editMeasurementTitle => 'Editar Medida';

  @override
  String get measurementDate => 'Fecha de Medida';

  @override
  String get weightRequired => 'Por favor ingresa peso';

  @override
  String get weightInvalid => 'Peso inválido (30-300kg)';

  @override
  String get bodyFatOptional => 'Grasa Corporal (opcional)';

  @override
  String get bodyFatInvalid => 'Inválido (0-50%)';

  @override
  String get muscleOptional => 'Masa Muscular (opcional)';

  @override
  String get waistOptional => 'Circunferencia de Cintura (opcional)';

  @override
  String get notesOptional => 'Notas (opcional)';

  @override
  String get notesHint =>
      'p.ej., en ayunas por la mañana, después del ejercicio...';

  @override
  String get measurementSaved => '¡Medida guardada!';

  @override
  String get advancedOptional => 'Avanzado (opcional)';

  @override
  String get goalRecTitle => 'Recomendación de Objetivo';

  @override
  String get bodyDataTitle => 'Tus Datos Corporales';

  @override
  String get weightLabel => 'Peso';

  @override
  String get weightInvalidRec => 'Por favor ingresa peso válido (30-300 kg)';

  @override
  String get heightRecLabel => 'Altura';

  @override
  String get heightRecInvalid => 'Por favor ingresa altura válida (100-250 cm)';

  @override
  String get birthdateLabel => 'Fecha de Nacimiento';

  @override
  String get birthdateSelect => 'Selecciona fecha';

  @override
  String birthdateDisplay(String date, int age) {
    return '$date  ($age años)';
  }

  @override
  String get birthdateSelectSnackbar =>
      'Por favor selecciona fecha de nacimiento';

  @override
  String get genderRecLabel => 'Género';

  @override
  String get activitySectionTitle => 'Tu Actividad';

  @override
  String get activityRecLabel => 'Nivel de Actividad';

  @override
  String get goalSectionTitle => 'Tu Objetivo';

  @override
  String get weightGoalRecLabel => 'Objetivo de Peso';

  @override
  String get calculateButton => 'Calcular Recomendación';

  @override
  String get calculating => 'Calculando...';

  @override
  String get recommendationTitle => 'Tu Recomendación';

  @override
  String trackingMethodLabel(String method) {
    return 'Método de seguimiento: $method';
  }

  @override
  String get bmrLabel => 'Tasa Metabólica Basal (TMB):';

  @override
  String get tdeeLabel => 'Gasto Energético Diario Total (TDEE):';

  @override
  String get targetCalories => 'Calorías Objetivo:';

  @override
  String get macronutrients => 'Macronutrientes';

  @override
  String get saveAsGoal => 'Guardar como Objetivo';

  @override
  String get saveBodyData => 'Guardar datos corporales para seguimiento';

  @override
  String get goalSaved => '¡Objetivo y datos corporales guardados!';

  @override
  String get goalSavedOnly => '¡Objetivo guardado!';

  @override
  String get goalSavedDialogTitle => '¡Objetivo Guardado!';

  @override
  String get goalSavedDialogContent =>
      'Tu objetivo nutricional ha sido guardado con éxito.';

  @override
  String goalTargetLine(int calories) {
    return 'Objetivo: $calories kcal/día';
  }

  @override
  String get toOverview => 'A la Descripción';

  @override
  String get personalizedRecTitle => 'Recomendación Personalizada';

  @override
  String get personalizedRecDesc =>
      'Basado en tus datos corporales calculamos tus necesidades calóricas individuales y recomendaciones de macronutrientes.';

  @override
  String get goalExplainLose =>
      'Con un déficit de ~500 kcal/día puedes perder aproximadamente 0.5 kg por semana.';

  @override
  String get goalExplainMaintain =>
      'Esta cantidad de calorías debería mantener tu peso actual.';

  @override
  String get goalExplainGain =>
      'Con un excedente de ~300 kcal/día puedes construir masa muscular de forma saludable.';

  @override
  String get trackingChooseTitle => 'Elegir Método de Seguimiento';

  @override
  String get trackingHowToTrack => '¿Cómo deseas hacer seguimiento?';

  @override
  String get trackingDescription =>
      'Elige el método que mejor se adapte a tu estilo de vida. Puedes cambiarlo en cualquier momento.';

  @override
  String get trackingRecommendedForYou => 'Tu Recomendación';

  @override
  String get trackingWhatToTrack => '¿Qué deberías hacer seguimiento?';

  @override
  String get trackingUseMethod => 'Usar Este Método';

  @override
  String get trackingMethodBmrOnlyName => 'BMR + Seguimiento';

  @override
  String get trackingMethodBmrOnlyShort =>
      'Haz seguimiento de todas las actividades';

  @override
  String get trackingMethodBmrOnlyDetail =>
      'Tu objetivo de calorías se basa únicamente en tu Tasa Metabólica Basal (BMR). Debes hacer seguimiento de TODAS las actividades físicas (caminar, ejercicio, tareas del hogar). Este método es el más preciso pero requiere seguimiento consistente.';

  @override
  String get trackingMethodBmrOnlyRecommended =>
      'Recomendado para:\n• Máxima precisión\n• Te gusta hacer seguimiento de todo\n• Niveles de actividad muy variables';

  @override
  String get trackingMethodBmrOnlyActivityHint =>
      'El Nivel de Actividad se ignora (siempre = 1.0)';

  @override
  String get trackingMethodBmrOnlyTrackingGuideline =>
      '✅ Hacer seguimiento: TODAS las actividades\n• Caminar (>10 min)\n• Ejercicio (gym, correr, etc.)\n• Tareas del hogar (limpiar, jardinería)\n• Subir escaleras (>5 pisos)';

  @override
  String get trackingMethodTdeeCompleteName => 'TDEE Completo';

  @override
  String get trackingMethodTdeeCompleteShort =>
      'Se necesita seguimiento mínimo';

  @override
  String get trackingMethodTdeeCompleteDetail =>
      'Tu objetivo de calorías se basa en tu Gasto Energético Total Diario (TDEE) incluyendo tu nivel de actividad. Tus actividades diarias ya están contabilizadas. Solo necesitas hacer seguimiento de actividades excepcionales (p.ej., caminata de 2 horas, maratón). Ideal para rutinas consistentes.';

  @override
  String get trackingMethodTdeeCompleteRecommended =>
      'Recomendado para:\n• Esfuerzo de seguimiento mínimo\n• Rutina diaria consistente\n• Ejercicio regular (misma cantidad)';

  @override
  String get trackingMethodTdeeCompleteActivityHint =>
      'Elige tu Nivel de Actividad basado en la actividad diaria TOTAL (incluyendo ejercicio)';

  @override
  String get trackingMethodTdeeCompleteTrackingGuideline =>
      '✅ Hacer seguimiento: Solo actividades excepcionales\n• Maratón / Media maratón\n• Caminata de todo el día\n• Sesiones de entrenamiento extra largas (>2h)\n\n❌ NO hacer seguimiento: Actividades diarias normales\n• Entrenamiento regular\n• Movimiento diario';

  @override
  String get trackingMethodTdeeHybridName => 'TDEE + Seguimiento de Deportes';

  @override
  String get trackingMethodTdeeHybridShort =>
      'Solo haz seguimiento de deportes';

  @override
  String get trackingMethodTdeeHybridDetail =>
      'Tu objetivo de calorías se basa en tu Gasto Energético Total Diario (TDEE) solo para la vida diaria. Elige tu Nivel de Actividad basado en tu trabajo diario (p.ej., trabajo de escritorio = sedentario). Haz seguimiento de todas las actividades de ejercicio (gym, correr, etc.) por separado. Ideal para rutinas de ejercicio variables.';

  @override
  String get trackingMethodTdeeHybridRecommended =>
      'Recomendado para:\n• Balance entre precisión y esfuerzo\n• Rutina de ejercicio variable\n• Separación clara entre diario y ejercicio';

  @override
  String get trackingMethodTdeeHybridActivityHint =>
      'Elige tu Nivel de Actividad SOLO basado en tu trabajo diario (sin ejercicio)';

  @override
  String get trackingMethodTdeeHybridTrackingGuideline =>
      '✅ Hacer seguimiento: Todas las actividades de ejercicio\n• Gym / Entrenamiento de fuerza\n• Correr / Trotar\n• Ciclismo\n• Natación\n• Clases de deportes\n\n❌ NO hacer seguimiento: Movimiento diario\n• Viaje al trabajo\n• Compras\n• Tareas del hogar normales';

  @override
  String get appSubtitle => 'Tu diario de nutrición personal';

  @override
  String get featureTrackTitle => 'Seguimiento de Calorías y Macros';

  @override
  String get featureTrackSubtitle => 'Registra y analiza comidas fácilmente';

  @override
  String get featureDatabaseTitle => 'Gran Base de Datos de Alimentos';

  @override
  String get featureDatabaseSubtitle =>
      'Open Food Facts, USDA y entradas propias';

  @override
  String get featureActivitiesTitle => 'Registrar Actividades';

  @override
  String get featureActivitiesSubtitle =>
      'Deporte y ejercicio en el balance diario';

  @override
  String get featureGoalsTitle => 'Objetivos Individuales';

  @override
  String get featureGoalsSubtitle =>
      'Recomendaciones basadas en tus datos corporales';

  @override
  String get loginWithGoogle => 'Iniciar sesión con Google';

  @override
  String get orContinueWith => 'O continuar con';

  @override
  String get loginWithEmail => 'Iniciar sesión con correo';

  @override
  String get signUpWithEmail => 'Registrarse';

  @override
  String get emailLabel => 'Correo electrónico';

  @override
  String get passwordLabel => 'Contraseña';

  @override
  String get nameOptionalLabel => 'Nombre (opcional)';

  @override
  String get passwordTooShort =>
      'Contraseña demasiado corta (mín. 8 caracteres)';

  @override
  String get alreadyHaveAccount => '¿Ya tienes cuenta? Iniciar sesión';

  @override
  String get noAccount => '¿Sin cuenta? Registrarse';

  @override
  String get signUpSuccess => '¡Registro exitoso!';

  @override
  String get privacyNote =>
      'Al iniciar sesión aceptas nuestra política de privacidad. Tus datos se almacenan de forma segura y no se comparten.';

  @override
  String get impressumLink => 'Aviso Legal y Privacidad';

  @override
  String loginFailed(String error) {
    return 'Error de inicio de sesión: $error';
  }

  @override
  String get infoTitle => 'Info y Aviso Legal';

  @override
  String get infoImpressumSection => 'Aviso Legal';

  @override
  String get infoPrivacySection => 'Privacidad';

  @override
  String get infoExternalServices => 'Servicios Externos y Fuentes de Datos';

  @override
  String get infoOpenSource => 'Bibliotecas de Código Abierto';

  @override
  String get infoDisclaimerSection => 'Descargo de Responsabilidad';

  @override
  String infoVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get infoDisclaimerText =>
      'Las recomendaciones nutricionales y los cálculos de calorías en esta aplicación se basan en fórmulas científicas y sirven solo como orientación. No reemplazan el asesoramiento profesional nutricional o médico.';

  @override
  String get infoTmgNotice => 'Información según § 5 TMG';

  @override
  String get infoContact => 'Contacto';

  @override
  String get infoEmail => 'Email: info@dietry.de';

  @override
  String get infoResponsible =>
      'Responsable del contenido según § 55 párr. 2 RStV: Thorsten Rieß (dirección como arriba)';

  @override
  String get infoDataStoredTitle => '¿Qué datos se almacenan?';

  @override
  String get infoDataGoogleAccount =>
      'Datos de cuenta de Google (email, nombre) para la autenticación';

  @override
  String get infoDataBody =>
      'Datos corporales (peso, altura, fecha de nacimiento, género)';

  @override
  String get infoDataMeals =>
      'Registros de comidas y base de datos de alimentos';

  @override
  String get infoDataActivities => 'Actividades y objetivos nutricionales';

  @override
  String get infoDataStorageText =>
      'Todos los datos se almacenan en una base de datos segura (Neon PostgreSQL). No se comparten datos con terceros. La autenticación se realiza mediante Google OAuth 2.0 a través de Neon Auth.';

  @override
  String get infoDataDeletion =>
      'Los datos pueden eliminarse en cualquier momento borrando la cuenta.';

  @override
  String get infoOpenSourceText =>
      'Esta aplicación fue desarrollada con Flutter y utiliza los siguientes paquetes:';

  @override
  String get infoOffDescription =>
      'Base de datos mundial de alimentos para información nutricional. Los datos están disponibles bajo la Open Database License (ODbL).';

  @override
  String get infoUsdaDescription =>
      'Base de datos de nutrientes alimentarios del Departamento de Agricultura de EE. UU.';

  @override
  String get infoNeonName => 'Neon (Base de datos y autenticación)';

  @override
  String get infoNeonDescription =>
      'Base de datos PostgreSQL sin servidor y servicio de autenticación OAuth 2.0.';

  @override
  String get infoNeonLicense => 'Servicio propietario';

  @override
  String get infoGoogleDescription =>
      'Autenticación mediante cuenta de Google. Solo se transmiten la dirección de correo electrónico y el nombre.';

  @override
  String get cannotNavigateToFuture => 'No puedes navegar al futuro';

  @override
  String noGoalForDate(String date) {
    return 'No hay objetivo nutricional para $date';
  }

  @override
  String get infoCopyright => '© 2025 Simon Span · dietry.de';

  @override
  String get offlineMode =>
      'Sin conexión – los cambios se sincronizarán al restaurar la conexión';

  @override
  String get pendingSyncCount => 'cambios pendientes de sincronización';

  @override
  String get syncNow => 'Sincronizar';

  @override
  String get appBarTitle => 'Dietry';

  @override
  String get profileTooltip => 'Perfil';

  @override
  String get infoTooltip => 'Info y Aviso Legal';

  @override
  String get languageTooltip => 'Cambiar idioma';

  @override
  String get logoutTooltip => 'Cerrar sesión';

  @override
  String get accountSectionTitle => 'Cuenta y datos';

  @override
  String get exportDataButton => 'Exportar datos';

  @override
  String get exportDataDescription =>
      'Descargar todas tus entradas como archivos CSV';

  @override
  String get deleteAccountButton => 'Eliminar cuenta';

  @override
  String get deleteAccountDescription =>
      'Eliminar permanentemente todos tus datos y cerrar sesión';

  @override
  String get deleteAccountConfirmTitle => '¿Realmente eliminar la cuenta?';

  @override
  String get deleteAccountConfirmText =>
      'Todas tus entradas de alimentos, actividades, mediciones corporales y objetivos se eliminarán permanentemente. Esta acción no se puede deshacer.';

  @override
  String get deleteAccountConfirmButton => 'Eliminar permanentemente';

  @override
  String get deleteAccountCredentialsHint =>
      'Nota: Debido a las limitaciones actuales del proveedor de autenticación (Neon Auth), tus credenciales de inicio de sesión no pueden eliminarse automáticamente junto con tus datos. Contacta con el soporte si también necesitas que se eliminen.';

  @override
  String get deleteAccountSuccess => 'Todos los datos han sido eliminados.';

  @override
  String get exportDataSuccess => 'Exportación exitosa';

  @override
  String exportDataError(String error) {
    return 'Error en la exportación: $error';
  }

  @override
  String deleteAccountError(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String get emailVerificationTitle => '¡Confirma tu correo electrónico!';

  @override
  String emailVerificationBody(String email) {
    return 'Hemos enviado un enlace de confirmación a $email. Haz clic en él para activar tu cuenta e inicia sesión.';
  }

  @override
  String get emailVerificationBack => 'Volver al inicio de sesión';

  @override
  String get forgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get resetPasswordTitle => 'Restablecer contraseña';

  @override
  String get sendResetLink => 'Enviar enlace';

  @override
  String get resetLinkSent => '¡Enlace enviado!';

  @override
  String resetLinkSentBody(String email) {
    return 'Hemos enviado un enlace de restablecimiento de contraseña a $email.';
  }

  @override
  String get waterTitle => 'Ingesta de agua';

  @override
  String waterGoalLabel(int amount) {
    return 'Objetivo: $amount ml';
  }

  @override
  String get waterAdd => 'Agregar agua';

  @override
  String get waterRemove => 'Quitar agua';

  @override
  String get devBannerText =>
      '⚠️ Versión preliminar · Base de datos de desarrollo · Los datos no se guardan permanentemente';

  @override
  String get waterGoalFieldLabel => 'Objetivo de agua';

  @override
  String get waterGoalFieldHint =>
      'Recomendación: aprox. 35 ml por kg de peso corporal';

  @override
  String get waterReminderTitle => 'Recordatorios de agua';

  @override
  String get waterReminderSubtitle => 'Recordar beber agua cada 4 horas';

  @override
  String get waterFromFood => 'de alimentos';

  @override
  String get waterManual => 'manual';

  @override
  String get cheatDayTitle => 'Día Trampa';

  @override
  String get cheatDayBanner =>
      '¡Día trampa! Disfrútalo — excluido de los informes.';

  @override
  String get markAsCheatDay => 'Día Trampa';

  @override
  String get cheatDayMarked => 'Día trampa marcado ✓';

  @override
  String get cheatDayRemoved => 'Día trampa eliminado';

  @override
  String cheatDayMonthlyNudge(int count) {
    return 'Has tenido $count días trampa este mes. ¡Sin problema, sin juicios!';
  }

  @override
  String streakDays(int count) {
    return 'Racha de $count días';
  }

  @override
  String get streakStart => '¡Empieza tu racha hoy!';

  @override
  String streakBestLabel(int count) {
    return 'Récord: $count';
  }

  @override
  String get streakMilestoneTitle => '¡Hito alcanzado!';

  @override
  String streakMilestoneBody(int count) {
    return 'Has completado una racha de $count días. ¡Sigue así!';
  }

  @override
  String get serverConfigButton => 'Configuración del servidor';

  @override
  String get serverConfigTitle => 'Configuración del servidor';

  @override
  String get serverConfigDescription =>
      'Para instalaciones autohospedadas puede apuntar la aplicación a sus propios endpoints de Neon PostgREST y Auth. Déjelo sin cambios para usar el servidor gestionado por defecto.';

  @override
  String get serverConfigDataApiUrl => 'URL de la API PostgREST';

  @override
  String get serverConfigAuthBaseUrl => 'URL base de autenticación';

  @override
  String get serverConfigCustomActive =>
      'Servidor personalizado activo — se usan sus propios endpoints.';

  @override
  String get serverConfigReset => 'Restablecer valores predeterminados';

  @override
  String get feedbackTitle => 'Enviar comentarios';

  @override
  String get feedbackTooltip => 'Enviar comentarios';

  @override
  String get feedbackEarlyAccessNote =>
      'Estás usando una versión de acceso anticipado. ¡Tu opinión nos ayuda a mejorar!';

  @override
  String get feedbackTypeLabel => 'Tipo';

  @override
  String get feedbackTypeBug => 'Error';

  @override
  String get feedbackTypeFeature => 'Sugerencia';

  @override
  String get feedbackTypeGeneral => 'General';

  @override
  String get feedbackRatingLabel => 'Valoración (opcional)';

  @override
  String get feedbackMessageLabel => 'Mensaje';

  @override
  String get feedbackMessageHint =>
      'Describe el error, tu idea o tu experiencia…';

  @override
  String get feedbackMessageTooShort =>
      'Por favor, escribe al menos 10 caracteres.';

  @override
  String get feedbackSubmit => 'Enviar';

  @override
  String get feedbackThankYou => '¡Gracias por tus comentarios!';

  @override
  String get reportsTitle => 'Informes';

  @override
  String get reportsRangeWeek => 'Semana';

  @override
  String get reportsRangeMonth => 'Mes';

  @override
  String get reportsRangeYear => 'Año';

  @override
  String get reportsRangeAllTime => 'Todo';

  @override
  String get reportsSummary => 'Resumen';

  @override
  String get reportsCalorieTrend => 'Tendencia calórica';

  @override
  String get reportsMacroAverage => 'Macros promedio';

  @override
  String get reportsWaterIntake => 'Consumo de agua';

  @override
  String get reportsBodyWeight => 'Peso corporal';

  @override
  String get reportsNoData => 'Sin datos para este período.';

  @override
  String get reportsAvgCalories => 'Kcal diarias promedio';

  @override
  String get reportsDaysTracked => 'Días registrados';

  @override
  String get reportsDaysOnTarget => 'Días en objetivo';

  @override
  String get reportsAvgWater => 'Agua diaria promedio';

  @override
  String get reportsGoalLine => 'Objetivo';

  @override
  String get reportsBodyFat => 'Grasa corporal %';

  @override
  String get reportsCaloriesBurned => 'Quemadas';

  @override
  String get reportsConsumed => 'Consumidas';

  @override
  String get reportsBalance => 'Balance';

  @override
  String get reportsUpsellBasic => 'Disponible en Cloud Edition (Basic+)';

  @override
  String get reportsUpsellPro => 'Disponible para usuarios Pro';

  @override
  String get reportsLoading => 'Cargando informes…';

  @override
  String get reportsExportTooltip => 'Exportar como CSV';

  @override
  String get reportsExportSuccess => 'Exportación correcta';

  @override
  String reportsExportError(String error) {
    return 'Error al exportar: $error';
  }

  @override
  String get macroOnlyMode => 'Solo macros (sin objetivo calórico)';
}
