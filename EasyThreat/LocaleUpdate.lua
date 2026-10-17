-- 0.4 controls and actionable diagnostic states, in all eight UI languages.
local locales={"enUS","deDE","frFR","esES","ptBR","ruRU","koKR","zhCN"}
local rows={
    {"Enemy filters","Gegnerfilter","Filtres ennemis","Filtros de enemigos","Filtros de inimigos","Фильтры врагов","적 필터","敌人筛选"},
    {"Marker size","Markierungsgröße","Taille des marques","Tamaño de marca","Tamanho da marca","Размер метки","징표 크기","标记大小"},
    {"Role icon size","Rollen-Icongröße","Taille icône de rôle","Tamaño icono de rol","Tamanho ícone de função","Размер значка роли","역할 아이콘 크기","职责图标大小"},
    {"Relative font size (%)","Relative Schriftgröße (%)","Taille du texte (%)","Tamaño del texto (%)","Tamanho do texto (%)","Размер шрифта (%)","상대 글꼴 크기 (%)","相对字号 (%)"},
    {"Play context","Spielmodus","Mode de jeu","Modo de juego","Modo de jogo","Режим игры","플레이 모드","游戏模式"},
    {"Solo","Solo","Solo","Solo","Solo","Соло","혼자","单人"},
    {"Party","Gruppe","Groupe","Grupo","Grupo","Группа","파티","小队"},
    {"Raid","Raid","Raid","Banda","Raide","Рейд","공격대","团队"},
    {"Enemy level","Gegnerlevel","Niveau ennemi","Nivel enemigo","Nível inimigo","Уровень врага","적 레벨","敌人等级"},
    {"Gray","Grau","Gris","Gris","Cinza","Серый","회색","灰色"},
    {"Green","Grün","Vert","Verde","Verde","Зелёный","녹색","绿色"},
    {"Yellow","Gelb","Jaune","Amarillo","Amarelo","Жёлтый","노란색","黄色"},
    {"Orange","Orange","Orange","Naranja","Laranja","Оранжевый","주황색","橙色"},
    {"Red","Rot","Rouge","Rojo","Vermelho","Красный","빨간색","红色"},
    {"Enemy type","Gegnertyp","Type ennemi","Tipo de enemigo","Tipo de inimigo","Тип врага","적 유형","敌人类型"},
    {"Normal","Normal","Normal","Normal","Normal","Обычный","일반","普通"},
    {"Rare","Selten","Rare","Raro","Raro","Редкий","희귀","稀有"},
    {"Elite","Elite","Élite","Élite","Elite","Элитный","정예","精英"},
    {"Rare elite","Seltene Elite","Élite rare","Élite raro","Elite raro","Редкий элитный","희귀 정예","稀有精英"},
    {"Boss","Boss","Boss","Jefe","Chefe","Босс","우두머리","首领"},
    {"Other types","Sonstige","Autres types","Otros tipos","Outros tipos","Другие типы","기타 유형","其他类型"},
    {"Raid list: marked enemies only","Raidliste: nur markierte Gegner","Liste raid : ennemis marqués","Lista de banda: solo marcados","Lista de raide: só marcados","Список рейда: только с метками","공격대 목록: 징표가 있는 적만","团队列表：仅已标记敌人"},
    {"Error","Fehler","Erreur","Error","Erro","Ошибка","오류","错误"},
    {"Warning","Warnung","Attention","Aviso","Aviso","Внимание","경고","警告"},
    {"Info","Hinweis","Info","Info","Info","Информация","안내","提示"},
    {"Server: no query in solo play; this is expected.","Server: Im Solospiel keine Abfrage vorgesehen. Das ist normal.","Serveur : aucune requête en solo, c’est normal.","Servidor: no se consulta en solitario; es normal.","Servidor: sem consultas solo; isso é normal.","Сервер: в соло запросов нет, это нормально.","서버: 혼자 플레이할 때 조회하지 않습니다. 정상입니다.","服务器：单人模式不发送查询，这是正常情况。"},
    {"Server: target an elite or boss in group combat to test replies.","Server: Zum Test in einer Gruppe einen kämpfenden Elitegegner oder Boss auswählen.","Serveur : ciblez un élite ou boss en combat de groupe pour tester.","Servidor: selecciona un élite o jefe en combate de grupo para probar.","Servidor: selecione um elite ou chefe em combate de grupo para testar.","Сервер: для проверки выберите элиту или босса в групповом бою.","서버: 파티 전투 중 정예나 우두머리를 선택하여 시험하세요.","服务器：请在组队战斗中选中精英或首领以测试回复。"},
    {"Server: target changed; briefly waiting to avoid mixing enemies.","Server: Ziel gewechselt. Kurze Pause verhindert die Zuordnung zum falschen Gegner.","Serveur : cible changée, courte pause pour éviter de mélanger les ennemis.","Servidor: cambio de objetivo; breve pausa para no mezclar enemigos.","Servidor: alvo alterado; breve pausa para não misturar inimigos.","Сервер: цель сменилась, короткая пауза защищает от смешения врагов.","서버: 대상이 바뀌어 적 데이터가 섞이지 않도록 잠시 기다립니다.","服务器：目标已更换，短暂等待以免混淆敌人。"},
    {"Server: waiting for a reply.","Server: Abfrage gesendet, Antwort steht noch aus.","Serveur : requête envoyée, réponse en attente.","Servidor: consulta enviada, esperando respuesta.","Servidor: consulta enviada, aguardando resposta.","Сервер: запрос отправлен, ожидается ответ.","서버: 조회를 보냈으며 응답을 기다리는 중입니다.","服务器：查询已发送，正在等待回复。"},
    {"Server: %d replies used for this target; context remains uncertain (~).","Server: %d Antworten für dieses Ziel genutzt. Zuordnung bleibt unsicher (~).","Serveur : %d réponses utilisées pour cette cible ; contexte incertain (~).","Servidor: %d respuestas usadas para este objetivo; contexto incierto (~).","Servidor: %d respostas usadas para este alvo; contexto incerto (~).","Сервер: использовано %d ответов для этой цели; привязка неточная (~).","서버: 현재 대상에 응답 %d개 사용. 대상 연결은 불확실합니다 (~).","服务器：此目标已采用%d条回复，目标关联仍不确定（~）。"},
    {"Server: no reply after %d requests. Record an elite fight with /et trace on.","Server: Nach %d Abfragen keine Antwort. Elitekampf mit /et trace on aufzeichnen.","Serveur : sans réponse après %d requêtes. Enregistrez un combat élite avec /et trace on.","Servidor: sin respuesta tras %d consultas. Registra un combate élite con /et trace on.","Servidor: sem resposta após %d consultas. Grave um combate elite com /et trace on.","Сервер: нет ответа на %d запросов. Запишите бой с элитой: /et trace on.","서버: 조회 %d회 후 응답이 없습니다. /et trace on으로 정예 전투를 기록하세요.","服务器：%d次查询后仍无回复。请用 /et trace on 记录精英战斗。"},
    {"Server: replies could not be assigned safely (%s). Use /et trace on.","Server: Antworten nicht sicher zuordenbar (%s). Mit /et trace on aufzeichnen.","Serveur : réponses non attribuables avec certitude (%s). Utilisez /et trace on.","Servidor: respuestas sin asignación segura (%s). Usa /et trace on.","Servidor: respostas sem atribuição segura (%s). Use /et trace on.","Сервер: ответы нельзя надёжно привязать (%s). Используйте /et trace on.","서버: 응답을 안전하게 연결할 수 없습니다 (%s). /et trace on을 사용하세요.","服务器：无法可靠关联回复（%s）。请使用 /et trace on。"},
    {"Server query overlaps another threat addon. Test with only one meter querying.","Serverabfrage überschneidet sich mit einem anderen Threat-Addon. Zum Test nur ein Meter abfragen lassen.","Requête en conflit avec un autre addon de menace. Testez avec un seul addon qui interroge.","Consulta solapada con otro addon de amenaza. Prueba con un solo medidor consultando.","Consulta sobreposta a outro addon de ameaça. Teste com apenas um medidor consultando.","Запрос совпал с запросом другого аддона угрозы. Проверяйте с одним запрашивающим аддоном.","다른 위협 애드온의 조회와 겹쳤습니다. 조회하는 애드온을 하나만 켜고 시험하세요.","查询与其他仇恨插件重叠。测试时请只让一个插件发起查询。"},
    {"Server messages unavailable. Reload the UI and check the client.","Servernachrichten nicht verfügbar. UI neu laden und Client prüfen.","Messages serveur indisponibles. Rechargez l’interface et vérifiez le client.","Mensajes del servidor no disponibles. Recarga la interfaz y revisa el cliente.","Mensagens do servidor indisponíveis. Recarregue a interface e verifique o cliente.","Сообщения сервера недоступны. Перезагрузите интерфейс и проверьте клиент.","서버 메시지를 사용할 수 없습니다. UI를 다시 불러오고 클라이언트를 확인하세요.","服务器消息不可用。请重载界面并检查客户端。"},
    {"Server request failed. Reload the UI; print diagnostics if it repeats.","Serverabfrage fehlgeschlagen. UI neu laden; bei Wiederholung Diagnose im Chat ausgeben.","Requête serveur échouée. Rechargez l’interface ; si cela persiste, affichez le diagnostic dans le chat.","Falló la consulta. Recarga la interfaz; si se repite, muestra el diagnóstico en el chat.","Falha na consulta. Recarregue a interface; se repetir, exiba o diagnóstico no chat.","Сбой запроса. Перезагрузите интерфейс; при повторе выведите диагностику в чат.","서버 조회 실패. UI를 다시 불러오고 반복되면 진단을 채팅에 출력하세요.","服务器查询失败。请重载界面；若再次发生，将诊断输出到聊天。"},
    {"Server: ready to query the selected enemy.","Server: Bereit zur Abfrage des ausgewählten Gegners.","Serveur : prêt à interroger l’ennemi sélectionné.","Servidor: listo para consultar el enemigo seleccionado.","Servidor: pronto para consultar o inimigo selecionado.","Сервер: готов к запросу по выбранному врагу.","서버: 선택한 적을 조회할 준비가 되었습니다.","服务器：已准备查询选中的敌人。"},
    {"Unknown packet format","unbekanntes Datenformat","format inconnu","formato desconocido","formato desconhecido","неизвестный формат","알 수 없는 형식","未知数据格式"},
    {"Unverified sender","Absender nicht verifiziert","expéditeur non vérifié","remitente no verificado","remetente não verificado","отправитель не проверен","미확인 발신자","发件方未验证"},
    {"Wrong channel","anderer Kanal","autre canal","otro canal","outro canal","другой канал","다른 채널","频道不符"},
    {"Expired reply","verspätete Antwort","réponse expirée","respuesta caducada","resposta expirada","ответ запоздал","만료된 응답","回复超时"},
    {"Changed target","Zielwechsel","cible changée","objetivo cambiado","alvo alterado","цель сменилась","대상 변경","目标已更换"},
    {"Overlapping query","überlappende Abfrage","requêtes simultanées","consultas solapadas","consultas sobrepostas","запросы пересекаются","조회 중복","查询重叠"},
    {"%s display disabled in Enemy filters.","Anzeige für %s unter Gegnerfilter ausgeschaltet.","Affichage %s désactivé dans Filtres ennemis.","Visualización de %s desactivada en Filtros de enemigos.","Exibição de %s desativada em Filtros de inimigos.","Отображение %s выключено в фильтрах врагов.","적 필터에서 %s 표시가 꺼져 있습니다.","敌人筛选中已关闭%s显示。"},
    {"Enemy hidden by filters. Check Enemy filters.","Gegner durch Filter ausgeblendet. Unter Gegnerfilter prüfen.","Ennemi masqué par les filtres. Vérifiez Filtres ennemis.","Enemigo oculto por filtros. Revisa Filtros de enemigos.","Inimigo oculto pelos filtros. Verifique Filtros de inimigos.","Враг скрыт фильтрами. Проверьте фильтры врагов.","필터로 적이 숨겨졌습니다. 적 필터를 확인하세요.","敌人被筛选条件隐藏。请检查敌人筛选。"},
    {"Raid support is experimental. Assign every tank in Roles.","Raid-Unterstützung ist experimentell. Alle Tanks unter Rollen zuweisen.","Prise en charge raid expérimentale. Assignez tous les tanks dans Rôles.","Soporte de banda experimental. Asigna todos los tanques en Roles.","Suporte a raide experimental. Atribua todos os tanques em Funções.","Поддержка рейда экспериментальная. Назначьте всех танков в разделе ролей.","공격대 지원은 실험적입니다. 역할에서 모든 탱커를 지정하세요.","团队支持为实验功能。请在职责中指定所有坦克。"},
}
for _,row in ipairs(rows) do
    for i,locale in ipairs(locales) do EasyThreat.translations[locale][row[1]]=row[i] end
end
local exportRows={
    {"Back","Zurück","Retour","Volver","Voltar","Назад","뒤로","返回"},
    {"Export settings","Einstellungen exportieren","Exporter les réglages","Exportar ajustes","Exportar configurações","Экспорт настроек","설정 내보내기","导出设置"},
    {"Select all","Alles markieren","Tout sélectionner","Seleccionar todo","Selecionar tudo","Выделить всё","모두 선택","全选"},
    {"Select all, then Ctrl+C. Paste into a text file to save.","Alles markieren, dann Strg+C. Zum Speichern in eine Textdatei einfügen.","Sélectionnez tout, puis Ctrl+C. Collez dans un fichier texte pour enregistrer.","Selecciona todo y pulsa Ctrl+C. Pega en un archivo de texto para guardar.","Selecione tudo e pressione Ctrl+C. Cole em um arquivo de texto para salvar.","Выделите всё и нажмите Ctrl+C. Вставьте в текстовый файл для сохранения.","모두 선택 후 Ctrl+C를 누르세요. 텍스트 파일에 붙여넣어 저장하세요.","全选后按 Ctrl+C，粘贴到文本文件中保存。"},
    {"Export failed. After exiting the game, copy SavedVariables/EasyThreat.lua.","Export fehlgeschlagen. Nach Beenden des Spiels SavedVariables/EasyThreat.lua kopieren.","Échec de l’export. Quittez le jeu puis copiez SavedVariables/EasyThreat.lua.","Falló la exportación. Sal del juego y copia SavedVariables/EasyThreat.lua.","Falha na exportação. Saia do jogo e copie SavedVariables/EasyThreat.lua.","Не удалось экспортировать. Выйдите из игры и скопируйте SavedVariables/EasyThreat.lua.","내보내기 실패. 게임 종료 후 SavedVariables/EasyThreat.lua를 복사하세요.","导出失败。退出游戏后复制 SavedVariables/EasyThreat.lua。"}
}
for _,row in ipairs(exportRows) do
    for i,locale in ipairs(locales) do EasyThreat.translations[locale][row[1]]=row[i] end
end
local importRows={
    {"Import settings outside combat.","Einstellungen außerhalb des Kampfes importieren.","Importez les réglages hors combat.","Importa los ajustes fuera de combate.","Importe os ajustes fora de combate.","Импортируйте настройки вне боя.","전투 중이 아닐 때 설정을 가져오세요.","请在脱离战斗后导入设置。"},
    {"Import settings","Einstellungen importieren","Importer les réglages","Importar ajustes","Importar configurações","Импорт настроек","설정 가져오기","导入设置"},
    {"Apply settings","Übernehmen","Appliquer","Aplicar","Aplicar","Применить","적용","应用"},
    {"Undo import","Import rückgängig","Annuler l’import","Deshacer importación","Desfazer importação","Отменить импорт","가져오기 취소","撤销导入"},
    {"Paste with Ctrl+V. Supplied settings replace current values; other settings stay unchanged.","Mit Strg+V einfügen. Enthaltene Einstellungen werden ersetzt, übrige bleiben erhalten.","Collez avec Ctrl+V. Les réglages fournis remplacent les valeurs actuelles ; les autres restent inchangés.","Pega con Ctrl+V. Se sustituyen los ajustes incluidos; los demás se conservan.","Cole com Ctrl+V. Os ajustes incluídos substituem os atuais; os demais permanecem.","Вставьте Ctrl+V. Указанные настройки заменятся, остальные сохранятся.","Ctrl+V로 붙여넣으세요. 포함된 설정만 교체하고 나머지는 유지합니다.","按 Ctrl+V 粘贴。仅替换其中包含的设置，保留其余设置。"},
    {"Settings applied. Undo is available until the next reload.","Einstellungen übernommen. Bis zum nächsten Neuladen rückgängig machbar.","Réglages appliqués. Annulation possible jusqu’au prochain rechargement.","Ajustes aplicados. Puedes deshacer hasta la próxima recarga.","Ajustes aplicados. É possível desfazer até a próxima recarga.","Настройки применены. Отмена доступна до перезагрузки интерфейса.","설정을 적용했습니다. 다음 UI 재시작 전까지 취소할 수 있습니다.","设置已应用，下次重载界面前可以撤销。"},
    {"Import too large or too deeply nested.","Import zu groß oder zu tief verschachtelt.","Import trop volumineux ou trop imbriqué.","Importación demasiado grande o anidada.","Importação grande demais ou muito aninhada.","Импорт слишком большой или вложенный.","가져올 데이터가 너무 크거나 중첩이 깊습니다.","导入内容过大或嵌套过深。"},
    {"Invalid settings text. Paste a complete EasyThreat export.","Ungültiges Format. Einen vollständigen EasyThreat-Export einfügen.","Format incorrect. Collez un export EasyThreat complet.","Formato incorrecto. Pega una exportación completa de EasyThreat.","Formato inválido. Cole uma exportação completa do EasyThreat.","Неверный формат. Вставьте полный экспорт EasyThreat.","잘못된 형식입니다. EasyThreat 내보내기 전체를 붙여넣으세요.","格式无效，请粘贴完整的 EasyThreat 导出内容。"},
    {"Duplicate setting in pasted text.","Eine Einstellung ist im eingefügten Text doppelt vorhanden.","Un réglage est présent en double.","Hay un ajuste duplicado en el texto.","Há um ajuste duplicado no texto.","В тексте есть повторяющаяся настройка.","붙여넣은 텍스트에 중복된 설정이 있습니다.","粘贴的文本包含重复设置。"},
    {"Wrong setting type","Falscher Datentyp","Type de réglage incorrect","Tipo de ajuste incorrecto","Tipo de ajuste incorreto","Неверный тип настройки","잘못된 설정 유형","设置类型错误"},
    {"Setting outside allowed values","Wert außerhalb des erlaubten Bereichs","Valeur non autorisée","Valor fuera del rango permitido","Valor fora do intervalo permitido","Недопустимое значение настройки","허용 범위를 벗어난 설정 값","设置值超出允许范围"},
    {"Unknown setting","Unbekannte Einstellung","Réglage inconnu","Ajuste desconocido","Ajuste desconhecido","Неизвестная настройка","알 수 없는 설정","未知设置"},
    {"Unsupported settings version","Nicht unterstützte Einstellungsversion","Version des réglages non prise en charge","Versión de ajustes no compatible","Versão de ajustes incompatível","Версия настроек не поддерживается","지원하지 않는 설정 버전","不支持的设置版本"},
    {"Could not apply settings. Previous settings restored.","Übernahme fehlgeschlagen. Bisherige Einstellungen wiederhergestellt.","Échec de l’application. Anciens réglages restaurés.","No se pudieron aplicar. Se restauraron los ajustes anteriores.","Não foi possível aplicar. Ajustes anteriores restaurados.","Не удалось применить. Прежние настройки восстановлены.","적용하지 못했습니다. 이전 설정을 복원했습니다.","无法应用设置，已恢复原设置。"}
}
for _,row in ipairs(importRows) do
    for i,locale in ipairs(locales) do EasyThreat.translations[locale][row[1]]=row[i] end
end
