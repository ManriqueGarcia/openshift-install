/**
 * Google Apps Script — Recibe tareas de Logseq y las inserta en el documento.
 *
 * INSTALACIÓN:
 * 1. Abre el Google Doc: https://docs.google.com/document/d/1aCwmE2S73LWzPWiG6qodRqtk6eCqSftrjfrmN_V9su0
 * 2. Menú: Extensiones > Apps Script
 * 3. Borra el contenido de Code.gs y pega TODO este archivo
 * 4. Guarda (Ctrl+S)
 * 5. Menú dentro de Apps Script: Implementar > Nueva implementación
 *    - Tipo: Aplicación web
 *    - Ejecutar como: Yo
 *    - Quién tiene acceso: Cualquier persona
 * 6. Copia la URL generada y pégala en ~/.config/logseq-gdoc.json como "web_app_url"
 * 7. La primera vez pedirá autorización — acéptala.
 */

function doPost(e) {
  try {
    var payload = JSON.parse(e.postData.contents);

    if (payload.action === "updateTasks") {
      var result = updateTasks(payload);
      return ContentService
        .createTextOutput(JSON.stringify(result))
        .setMimeType(ContentService.MimeType.JSON);
    }

    return ContentService
      .createTextOutput(JSON.stringify({status: "error", message: "Acción desconocida"}))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({status: "error", message: err.toString()}))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function updateTasks(payload) {
  var docId = payload.docId;
  var heading = payload.heading;
  var tasks = payload.tasks;
  var client = payload.client;
  var timestamp = payload.timestamp;

  var doc = DocumentApp.openById(docId);
  var body = doc.getBody();

  var headingIndex = findHeading(body, heading);
  if (headingIndex === -1) {
    return {status: "error", message: "No se encontró la sección '" + heading + "'"};
  }

  // Eliminar contenido anterior entre el heading y el siguiente heading del mismo nivel
  var endIndex = findNextHeadingSameLevel(body, headingIndex);
  removeElementsBetween(body, headingIndex + 1, endIndex);

  // Insertar timestamp
  var insertAt = headingIndex + 1;
  var tsStyle = {};
  tsStyle[DocumentApp.Attribute.FONT_SIZE] = 9;
  tsStyle[DocumentApp.Attribute.ITALIC] = true;
  tsStyle[DocumentApp.Attribute.FOREGROUND_COLOR] = "#888888";
  var tsParagraph = body.insertParagraph(insertAt, "Actualizado: " + timestamp);
  tsParagraph.setAttributes(tsStyle);
  insertAt++;

  // Insertar línea vacía
  body.insertParagraph(insertAt, "");
  insertAt++;

  // Agrupar tareas por estado
  var groups = {};
  var groupOrder = ["▶️ En progreso", "📝 Por hacer", "📝 Aplazada", "⏳ Esperando"];

  tasks.forEach(function(task) {
    var label = task.state_label;
    if (!groups[label]) groups[label] = [];
    groups[label].push(task);
  });

  groupOrder.forEach(function(groupLabel) {
    var groupTasks = groups[groupLabel];
    if (!groupTasks || groupTasks.length === 0) return;

    // Subtítulo del grupo
    var subHeading = body.insertParagraph(insertAt, groupLabel + " (" + groupTasks.length + ")");
    subHeading.setHeading(DocumentApp.ParagraphHeading.HEADING3);
    var subStyle = {};
    subStyle[DocumentApp.Attribute.FONT_SIZE] = 11;
    subStyle[DocumentApp.Attribute.BOLD] = true;
    subHeading.setAttributes(subStyle);
    insertAt++;

    groupTasks.forEach(function(task) {
      var prioIcon = task.priority_label || "";
      var bulletText = prioIcon + " " + task.text;

      var listItem = body.insertListItem(insertAt, bulletText.trim());
      listItem.setGlyphType(DocumentApp.GlyphType.BULLET);

      // Poner el icono de prioridad en negrita
      if (prioIcon) {
        listItem.editAsText().setBold(0, prioIcon.length, true);
      }

      var itemStyle = {};
      itemStyle[DocumentApp.Attribute.FONT_SIZE] = 10;
      listItem.setAttributes(itemStyle);
      // Mantener el icono en negrita después de setAttributes
      if (prioIcon) {
        listItem.editAsText().setBold(0, prioIcon.length, true);
      }

      insertAt++;
    });

    // Línea vacía entre grupos
    body.insertParagraph(insertAt, "");
    insertAt++;
  });

  return {
    status: "ok",
    message: tasks.length + " tareas insertadas en '" + heading + "'"
  };
}

function findHeading(body, headingText) {
  var numChildren = body.getNumChildren();
  for (var i = 0; i < numChildren; i++) {
    var child = body.getChild(i);
    if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
      var paragraph = child.asParagraph();
      var pHeading = paragraph.getHeading();
      if (pHeading !== DocumentApp.ParagraphHeading.NORMAL) {
        var text = paragraph.getText().trim().toLowerCase();
        if (text === headingText.toLowerCase()) {
          return i;
        }
      }
    }
  }
  return -1;
}

function findNextHeadingSameLevel(body, headingIndex) {
  var numChildren = body.getNumChildren();
  var baseHeading = body.getChild(headingIndex).asParagraph().getHeading();

  for (var i = headingIndex + 1; i < numChildren; i++) {
    var child = body.getChild(i);
    if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
      var pHeading = child.asParagraph().getHeading();
      if (pHeading !== DocumentApp.ParagraphHeading.NORMAL && isHeadingSameOrHigher(pHeading, baseHeading)) {
        return i;
      }
    }
  }
  return numChildren;
}

function isHeadingSameOrHigher(a, b) {
  var order = [
    DocumentApp.ParagraphHeading.HEADING1,
    DocumentApp.ParagraphHeading.HEADING2,
    DocumentApp.ParagraphHeading.HEADING3,
    DocumentApp.ParagraphHeading.HEADING4,
    DocumentApp.ParagraphHeading.HEADING5,
    DocumentApp.ParagraphHeading.HEADING6,
  ];
  return order.indexOf(a) <= order.indexOf(b);
}

function removeElementsBetween(body, startIndex, endIndex) {
  for (var i = endIndex - 1; i >= startIndex; i--) {
    body.removeChild(body.getChild(i));
  }
}

/**
 * DIAGNÓSTICO: Lista todos los headings del documento.
 * Ejecutar > listHeadings → mira el log (Ver > Registros)
 */
function listHeadings() {
  var doc = DocumentApp.openById("1aCwmE2S73LWzPWiG6qodRqtk6eCqSftrjfrmN_V9su0");
  var body = doc.getBody();
  var n = body.getNumChildren();
  Logger.log("Total de elementos: " + n);
  for (var i = 0; i < n; i++) {
    var child = body.getChild(i);
    if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
      var p = child.asParagraph();
      var h = p.getHeading();
      if (h !== DocumentApp.ParagraphHeading.NORMAL) {
        Logger.log("[" + i + "] " + h + " → '" + p.getText() + "'");
      }
    }
  }
}

/**
 * EXPORTAR DOCUMENTO → JSON para generar acta en Logseq.
 *
 * Ejecutar > exportToLogseq → guarda un archivo JSON en Google Drive.
 * El log muestra el enlace de descarga. Descárgalo y pásalo a:
 *   gdoc-to-logseq bbva -f ~/Descargas/logseq-export-*.json
 */
function exportToLogseq() {
  var doc = DocumentApp.openById("1aCwmE2S73LWzPWiG6qodRqtk6eCqSftrjfrmN_V9su0");
  var body = doc.getBody();
  var n = body.getNumChildren();
  var title = doc.getName();

  var sections = [];
  var currentSection = null;

  for (var i = 0; i < n; i++) {
    var child = body.getChild(i);
    var elType = child.getType();

    if (elType === DocumentApp.ElementType.PARAGRAPH) {
      var p = child.asParagraph();
      var heading = p.getHeading();
      var text = p.getText().trim();

      if (heading !== DocumentApp.ParagraphHeading.NORMAL && text) {
        currentSection = {
          heading: text,
          level: headingLevel_(heading),
          items: []
        };
        sections.push(currentSection);
      } else if (text) {
        if (!currentSection) {
          currentSection = {heading: "(Inicio)", level: 0, items: []};
          sections.push(currentSection);
        }
        currentSection.items.push({type: "text", content: text});
      }
    } else if (elType === DocumentApp.ElementType.LIST_ITEM) {
      var li = child.asListItem();
      var text = li.getText().trim();
      var nesting = li.getNestingLevel();
      if (text) {
        if (!currentSection) {
          currentSection = {heading: "(Inicio)", level: 0, items: []};
          sections.push(currentSection);
        }
        currentSection.items.push({type: "list", content: text, indent: nesting});
      }
    } else if (elType === DocumentApp.ElementType.TABLE) {
      var table = child.asTable();
      var rows = [];
      for (var r = 0; r < table.getNumRows(); r++) {
        var row = table.getRow(r);
        var cells = [];
        for (var c = 0; c < row.getNumCells(); c++) {
          cells.push(row.getCell(c).getText().trim());
        }
        rows.push(cells);
      }
      if (!currentSection) {
        currentSection = {heading: "(Inicio)", level: 0, items: []};
        sections.push(currentSection);
      }
      currentSection.items.push({type: "table", rows: rows});
    }
  }

  var output = {
    title: title,
    exported: new Date().toISOString(),
    sections: sections
  };

  var json = JSON.stringify(output, null, 2);

  var timestamp = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), "yyyy-MM-dd_HHmm");
  var filename = "logseq-export-" + timestamp + ".json";
  var file = DriveApp.createFile(filename, json, MimeType.PLAIN_TEXT);
  file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);

  var downloadUrl = "https://drive.google.com/uc?export=download&id=" + file.getId();

  Logger.log("✅ Archivo creado: " + filename);
  Logger.log("📂 Abrir en Drive: " + file.getUrl());
  Logger.log("⬇️  Descarga directa: " + downloadUrl);
  Logger.log("Secciones exportadas: " + sections.length);

  return downloadUrl;
}

function headingLevel_(heading) {
  var levels = {};
  levels[DocumentApp.ParagraphHeading.HEADING1] = 1;
  levels[DocumentApp.ParagraphHeading.HEADING2] = 2;
  levels[DocumentApp.ParagraphHeading.HEADING3] = 3;
  levels[DocumentApp.ParagraphHeading.HEADING4] = 4;
  levels[DocumentApp.ParagraphHeading.HEADING5] = 5;
  levels[DocumentApp.ParagraphHeading.HEADING6] = 6;
  return levels[heading] || 0;
}

/**
 * OPCIÓN 1: Ejecutar directamente desde el editor de Apps Script.
 *
 * 1. Ejecuta "logseq-to-gdoc bbva --dry-run" en tu terminal
 * 2. Copia el JSON que genera
 * 3. Pégalo en la variable TASKS_JSON de abajo (reemplazando el array vacío)
 * 4. En el editor de Apps Script: Ejecutar > runFromEditor
 *
 * O usa OPCIÓN 2 (más abajo) si la web app funciona.
 */
function runFromEditor() {
  var TASKS_JSON = [
  {
    "state": "DOING",
    "priority": "A",
    "text": "[RH JIRA] Updates for RFE-7717: Enable sso/auth authentication for the argo cli --> Revisar lo que indican en el ticket para ver si es válido para BBVA",
    "state_label": "▶️ En progreso",
    "priority_label": "🔴"
  },
  {
    "state": "NOW",
    "priority": "A",
    "text": "SE para GitOps 1.17",
    "state_label": "▶️ En progreso",
    "priority_label": "🔴"
  },
  {
    "state": "TODO",
    "priority": "A",
    "text": "cambiar reunión del día 7 porque estaré en Madrid para visitar a Mapfre",
    "state_label": "📝 Por hacer",
    "priority_label": "🔴"
  },
  {
    "state": "NOW",
    "priority": "B",
    "text": "BUG Documentación por plataforma ocpv",
    "state_label": "▶️ En progreso",
    "priority_label": "🟡"
  },
  {
    "state": "TODO",
    "priority": "B",
    "text": "Revisar cuál va a ser la última versión de OpenShift 4 y cuándo sale OpenShift 5",
    "state_label": "📝 Por hacer",
    "priority_label": "🟡"
  },
  {
    "state": "TODO",
    "priority": "B",
    "text": "la pregunta en payments si lo que está pasando",
    "state_label": "📝 Por hacer",
    "priority_label": "🟡"
  },
  {
    "state": "TODO",
    "priority": "B",
    "text": "Revisar RFE de Gitops con Harriet Lawrence para ver si se van a hacer o no",
    "state_label": "📝 Por hacer",
    "priority_label": "🟡"
  },
  {
    "state": "TODO",
    "priority": "B",
    "text": "Para comentar, ya están desplegando clusters en physics 3.0, parece que David se ha quedado tranquilo, ya están desplegando, esto les aprieta",
    "state_label": "📝 Por hacer",
    "priority_label": "🟡"
  },
  {
    "state": "TODO",
    "priority": "B",
    "text": "revisar tema de operadores de Flink y Hazelcast si hay algo al respecto. Pero todavía no están como certified y piden abrir reglas en GHCR para poder descargar de docker",
    "state_label": "📝 Por hacer",
    "priority_label": "🟡"
  }
];

  var payload = {
    docId: "1aCwmE2S73LWzPWiG6qodRqtk6eCqSftrjfrmN_V9su0",
    heading: "Tareas pendientes",
    client: "BBVA",
    timestamp: new Date().toLocaleString("es-ES"),
    tasks: TASKS_JSON
  };

  var result = updateTasks(payload);
  Logger.log(result);
}

/**
 * OPCIÓN 2: Función de prueba con datos de ejemplo.
 * Ejecutar > testInsert
 */
function testInsert() {
  var payload = {
    docId: "1aCwmE2S73LWzPWiG6qodRqtk6eCqSftrjfrmN_V9su0",
    heading: "Tareas pendientes",
    client: "BBVA",
    timestamp: new Date().toLocaleString("es-ES"),
    tasks: [
      {state: "NOW", priority: "A", text: "Tarea de prueba — puedes borrar esto", state_label: "▶️ En progreso", priority_label: "🔴"},
      {state: "TODO", priority: "B", text: "Otra tarea de prueba", state_label: "📝 Por hacer", priority_label: "🟡"},
    ]
  };

  var result = updateTasks(payload);
  Logger.log(result);
}
