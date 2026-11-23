/* =====================================================================
   WorkHub - MongoDB : aggregation pipelines (HR reports)
   Run: mongosh "mongodb://localhost:27017" --file mongodb/03_aggregation_pipelines.js
   Read-only. In mongosh you can also paste any single pipeline.
   ===================================================================== */

db = db.getSiblingDB("WorkHubDB");
const show = (title, docs) => { print(`\n=== ${title} ===`); docs.forEach(d => printjson(d)); };

/* 1. Skills inventory: how many people have each skill, average level, experts */
show("1. Skills inventory (top 8)", db.employee_profiles.aggregate([
  { $unwind: "$skills" },
  { $group: {
      _id: "$skills.name",
      people:   { $sum: 1 },
      avgLevel: { $avg: "$skills.level" },
      experts:  { $push: { $cond: [{ $gte: ["$skills.level", 4] }, { $concat: ["$name.first", " ", "$name.last"] }, "$$REMOVE"] } }
  } },
  { $project: { _id: 0, skill: "$_id", people: 1, avgLevel: { $round: ["$avgLevel", 2] }, experts: 1 } },
  { $sort: { people: -1, skill: 1 } },
  { $limit: 8 }
]));

/* 2. Skill coverage per department: distinct skills and certified people */
show("2. Skill coverage by department", db.employee_profiles.aggregate([
  { $group: {
      _id: "$department.name",
      headcount:      { $sum: 1 },
      skillSets:      { $push: "$skills.name" },
      certifiedStaff: { $sum: { $cond: [{ $gt: [{ $size: { $ifNull: ["$certifications", []] } }, 0] }, 1, 0] } }
  } },
  { $project: {
      _id: 0, department: "$_id", headcount: 1, certifiedStaff: 1,
      distinctSkills: { $size: { $setUnion: { $reduce: { input: "$skillSets", initialValue: [], in: { $setUnion: ["$$value", "$$this"] } } } } }
  } },
  { $sort: { distinctSkills: -1, department: 1 } }
]));

/* 3. 360 feedback by cycle and department ($lookup joins two collections) */
show("3. Average 360 rating by cycle and department", db.review_feedback.aggregate([
  { $lookup: { from: "employee_profiles", localField: "employeeId", foreignField: "employeeId", as: "emp" } },
  { $unwind: "$emp" },
  { $group: {
      _id: { cycle: "$cycle", department: "$emp.department.name" },
      responses: { $sum: 1 },
      avgRating: { $avg: "$rating" }
  } },
  { $project: { _id: 0, cycle: "$_id.cycle", department: "$_id.department", responses: 1, avgRating: { $round: ["$avgRating", 2] } } },
  { $sort: { cycle: 1, avgRating: -1 } }
]).toArray().slice(0, 8));

/* 4. Most mentioned strengths and improvement areas in the 2026 cycle ($facet = two reports in one pass) */
show("4. Top strengths / improvements (2026)", db.review_feedback.aggregate([
  { $match: { cycle: 2026 } },
  { $facet: {
      strengths: [
        { $unwind: "$strengths" },
        { $group: { _id: "$strengths", mentions: { $sum: 1 } } },
        { $sort: { mentions: -1, _id: 1 } }, { $limit: 3 }
      ],
      improvements: [
        { $unwind: "$improvements" },
        { $group: { _id: "$improvements", mentions: { $sum: 1 } } },
        { $sort: { mentions: -1, _id: 1 } }, { $limit: 3 }
      ]
  } }
]));

/* 5. Employees needing attention: average 360 rating below 3 in any cycle */
show("5. Average 360 rating below 3", db.review_feedback.aggregate([
  { $group: { _id: { employeeId: "$employeeId", cycle: "$cycle" }, avgRating: { $avg: "$rating" }, responses: { $sum: 1 } } },
  { $match: { avgRating: { $lt: 3 } } },
  { $lookup: { from: "employee_profiles", localField: "_id.employeeId", foreignField: "employeeId", as: "emp" } },
  { $project: {
      _id: 0, employeeId: "$_id.employeeId", cycle: "$_id.cycle",
      name: { $concat: [{ $first: "$emp.name.first" }, " ", { $first: "$emp.name.last" }] },
      avgRating: { $round: ["$avgRating", 2] }, responses: 1
  } },
  { $sort: { avgRating: 1, employeeId: 1 } }
]));

/* 6. Certifications expiring in the next 90 days ($dateDiff) */
const today = new Date("2026-11-22T00:00:00Z");
show("6. Certifications expiring within 90 days of 2026-11-22", db.employee_profiles.aggregate([
  { $unwind: "$certifications" },
  { $match: { "certifications.expiresOn": { $gte: today, $lte: new Date(today.getTime() + 90 * 86400000) } } },
  { $project: {
      _id: 0, employeeId: 1, name: { $concat: ["$name.first", " ", "$name.last"] },
      certification: "$certifications.name", expiresOn: "$certifications.expiresOn",
      daysLeft: { $dateDiff: { startDate: today, endDate: "$certifications.expiresOn", unit: "day" } }
  } },
  { $sort: { daysLeft: 1 } }
]));

/* 7. Notification dashboard: by type, by status, busiest recipients */
show("7. Notification dashboard", db.hr_notifications.aggregate([
  { $facet: {
      byType:   [{ $group: { _id: "$type", count: { $sum: 1 } } }, { $sort: { count: -1 } }],
      byStatus: [{ $group: { _id: "$status", count: { $sum: 1 } } }, { $sort: { _id: 1 } }],
      unreadByRecipient: [
        { $match: { status: { $ne: "Read" } } },
        { $group: { _id: "$recipientId", unread: { $sum: 1 } } },
        { $sort: { unread: -1, _id: 1 } }, { $limit: 3 }
      ]
  } }
]));
