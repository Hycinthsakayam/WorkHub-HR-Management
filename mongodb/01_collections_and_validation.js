/* =====================================================================
   WorkHub - MongoDB : collections, $jsonSchema validation, indexes
   Run: mongosh "mongodb://localhost:27017" --file mongodb/01_collections_and_validation.js
   Re-runnable: drops and recreates the three collections.

   SQL Server keeps the relational, transactional data (employees, leave,
   timesheets, payroll). MongoDB keeps document-shaped data whose structure
   varies per employee or grows as lists:
     employee_profiles  skills, certifications, languages, emergency contact
     review_feedback    360-degree feedback: strengths / improvements lists
     hr_notifications   reminders and events produced by the HR workflows
   employeeId in every document is the EmployeeID from SQL Server.
   ===================================================================== */

db = db.getSiblingDB("WorkHubDB");

["employee_profiles", "review_feedback", "hr_notifications"].forEach(name => db.getCollection(name).drop());

/* ---------------------------------------------------------------------
   1. employee_profiles
   --------------------------------------------------------------------- */
db.createCollection("employee_profiles", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Employee profile",
      required: ["employeeId", "name", "email", "department", "role", "skills", "updatedAt"],
      additionalProperties: false,
      properties: {
        _id:        { bsonType: "objectId" },
        employeeId: { bsonType: "int", minimum: 1, description: "EmployeeID from SQL Server - required" },
        name: {
          bsonType: "object", required: ["first", "last"], additionalProperties: false,
          properties: {
            first: { bsonType: "string", minLength: 1, maxLength: 50 },
            last:  { bsonType: "string", minLength: 1, maxLength: 50 }
          }
        },
        email:      { bsonType: "string", pattern: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", description: "valid email - required" },
        role:       { enum: ["Employee", "Manager"] },
        department: {
          bsonType: "object", required: ["id", "name"],
          properties: {
            id:    { bsonType: "int", minimum: 1 },
            name:  { bsonType: "string" },
            plant: { bsonType: "string" },
            city:  { bsonType: "string" }
          }
        },
        skills: {
          bsonType: "array", minItems: 1, uniqueItems: true,
          items: {
            bsonType: "object", required: ["name", "level"], additionalProperties: false,
            properties: {
              name:  { bsonType: "string", minLength: 2 },
              level: { bsonType: "int", minimum: 1, maximum: 5, description: "1 = beginner ... 5 = expert" }
            }
          }
        },
        certifications: {
          bsonType: "array",
          items: {
            bsonType: "object", required: ["name", "issuedOn"],
            properties: {
              name:      { bsonType: "string" },
              issuedOn:  { bsonType: "date" },
              expiresOn: { bsonType: ["date", "null"] }
            }
          }
        },
        languages: { bsonType: "array", items: { bsonType: "string" } },
        emergencyContact: {
          bsonType: "object", required: ["name", "phone"],
          properties: {
            name:     { bsonType: "string" },
            relation: { bsonType: "string" },
            phone:    { bsonType: "string", pattern: "^\\+?[0-9 -]{10,15}$" }
          }
        },
        updatedAt: { bsonType: "date" }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});
db.employee_profiles.createIndex({ employeeId: 1 }, { unique: true, name: "ux_employeeId" });
db.employee_profiles.createIndex({ email: 1 }, { unique: true, name: "ux_email" });
db.employee_profiles.createIndex({ "skills.name": 1, "skills.level": -1 }, { name: "ix_skills" });
db.employee_profiles.createIndex({ "department.id": 1 }, { name: "ix_department" });

/* ---------------------------------------------------------------------
   2. review_feedback (360-degree feedback)
   --------------------------------------------------------------------- */
db.createCollection("review_feedback", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "360 review feedback",
      required: ["employeeId", "cycle", "givenBy", "rating", "submittedAt"],
      properties: {
        employeeId: { bsonType: "int", minimum: 1 },
        cycle:      { bsonType: "int", minimum: 2000, maximum: 2100, description: "review cycle = calendar year" },
        givenBy: {
          bsonType: "object", required: ["employeeId", "relationship"],
          properties: {
            employeeId:   { bsonType: "int", minimum: 1 },
            relationship: { enum: ["Manager", "Peer", "DirectReport", "Self"] }
          }
        },
        rating:       { bsonType: "int", minimum: 1, maximum: 5, description: "1-5 inclusive, same rule as SQL" },
        strengths:    { bsonType: "array", maxItems: 5, items: { bsonType: "string" } },
        improvements: { bsonType: "array", maxItems: 5, items: { bsonType: "string" } },
        comments:     { bsonType: "string", maxLength: 500 },
        submittedAt:  { bsonType: "date" }
      }
    }
  },
  validationAction: "error"
});
// One piece of feedback per giver, per employee, per cycle (the Mongo version of DuplicateReview)
db.review_feedback.createIndex({ employeeId: 1, cycle: 1, "givenBy.employeeId": 1 }, { unique: true, name: "ux_one_feedback_per_giver_per_cycle" });
db.review_feedback.createIndex({ cycle: 1, rating: -1 }, { name: "ix_cycle_rating" });

/* ---------------------------------------------------------------------
   3. hr_notifications
   --------------------------------------------------------------------- */
db.createCollection("hr_notifications", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["type", "recipientId", "message", "channel", "status", "createdAt"],
      properties: {
        type:              { enum: ["REVIEW_REMINDER", "LEAVE_APPROVED", "LEAVE_REJECTED", "PAYROLL_READY", "WAITLIST_PROMOTED", "CERTIFICATION_EXPIRING"] },
        recipientId:       { bsonType: "int", minimum: 1 },
        subjectEmployeeId: { bsonType: ["int", "null"] },
        message:           { bsonType: "string", minLength: 5, maxLength: 300 },
        channel:           { enum: ["Email", "InApp", "SMS"] },
        status:            { enum: ["Queued", "Sent", "Read"] },
        createdAt:         { bsonType: "date" },
        readAt:            { bsonType: ["date", "null"] }
      }
    }
  },
  validationAction: "error"
});
db.hr_notifications.createIndex({ recipientId: 1, status: 1 }, { name: "ix_recipient_status" });
db.hr_notifications.createIndex({ type: 1, createdAt: -1 }, { name: "ix_type_created" });

print("Collections created in WorkHubDB:");
db.getCollectionInfos().forEach(c =>
  print(`  ${c.name.padEnd(20)} validator: ${c.options.validator ? "yes" : "no"}, action: ${c.options.validationAction}`));
