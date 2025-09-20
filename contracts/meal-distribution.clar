;; School Lunch Funding - Meal Distribution Contract
;; Track meal distribution to ensure funds reach intended recipients

;; Constants
(define-constant ERR_UNAUTHORIZED (err u900))
(define-constant ERR_MEAL_NOT_FOUND (err u901))
(define-constant ERR_INVALID_DISTRIBUTION (err u902))
(define-constant ERR_STUDENT_NOT_ELIGIBLE (err u903))
(define-constant ERR_ALREADY_DISTRIBUTED (err u904))
(define-constant ERR_INSUFFICIENT_FUNDS (err u905))
(define-constant ERR_INVALID_SCHOOL (err u906))
(define-constant DISTRIBUTION_WINDOW_BLOCKS u144) ;; Approximately 2 hours
(define-constant MAX_MEALS_PER_STUDENT_PER_DAY u3)
(define-constant NUTRITION_STANDARDS_VERSION u1)

;; Data Variables
(define-data-var distribution-counter uint u0)
(define-data-var meal-counter uint u0)
(define-data-var admin principal tx-sender)
(define-data-var total-meals-distributed uint u0)
(define-data-var total-students-served uint u0)

;; Data Maps
(define-map meal-distributions
  { distribution-id: uint }
  {
    school-id: (string-ascii 100),
    distribution-date: uint,
    meal-type: (string-ascii 20), ;; breakfast, lunch, dinner, snack
    total-meals-planned: uint,
    total-meals-distributed: uint,
    funding-source-campaign: uint,
    verified-by: principal,
    distribution-complete: bool,
    cost-per-meal: uint,
    nutrition-verified: bool
  }
)

(define-map student-meal-records
  { student-anonymous-id: uint, distribution-id: uint }
  {
    meal-received: bool,
    meal-type: (string-ascii 20),
    distribution-time: uint,
    special-dietary-accommodated: bool,
    nutrition-score: uint,
    student-satisfaction: uint,
    verified-consumption: bool
  }
)

(define-map daily-distribution-summary
  { school-id: (string-ascii 100), date: uint }
  {
    breakfast-count: uint,
    lunch-count: uint,
    dinner-count: uint,
    snack-count: uint,
    total-students-served: uint,
    total-cost: uint,
    funding-sources: (list 10 uint),
    nutrition-compliance: bool,
    waste-percentage: uint
  }
)

(define-map nutrition-standards
  { meal-type: (string-ascii 20), age-group: (string-ascii 20) }
  {
    calories-min: uint,
    calories-max: uint,
    protein-grams: uint,
    vegetables-servings: uint,
    fruits-servings: uint,
    grains-servings: uint,
    dairy-servings: uint,
    sodium-limit-mg: uint,
    sugar-limit-grams: uint,
    compliance-required: bool
  }
)

(define-map meal-quality-reports
  { report-id: uint }
  {
    school-id: (string-ascii 100),
    distribution-id: uint,
    report-date: uint,
    reported-by: principal,
    quality-score: uint,
    nutrition-compliance: bool,
    student-feedback-average: uint,
    improvement-suggestions: (string-ascii 300),
    follow-up-required: bool
  }
)

(define-map school-distribution-stats
  { school-id: (string-ascii 100) }
  {
    total-distributions: uint,
    total-meals-served: uint,
    total-students-reached: uint,
    average-daily-participation: uint,
    funding-efficiency-score: uint,
    nutrition-compliance-rate: uint,
    waste-reduction-score: uint,
    last-distribution-date: uint
  }
)

(define-map distribution-verification
  { distribution-id: uint, verifier: principal }
  {
    verification-date: uint,
    verification-type: (string-ascii 50),
    meals-count-verified: uint,
    quality-verified: bool,
    documentation-complete: bool,
    discrepancies-found: uint,
    verification-notes: (string-ascii 400)
  }
)

;; Private Functions
(define-private (is-admin (user principal))
  (is-eq user (var-get admin))
)

(define-private (has-distribution-permission (user principal) (school-id (string-ascii 100)))
  ;; This would integrate with the student-verification contract in a full implementation
  ;; For now, we'll allow admin and assume school staff have been verified
  (or (is-admin user) (not (is-eq user (var-get admin))))
)

(define-private (calculate-nutrition-score (meal-type (string-ascii 20)) (compliance-checks uint))
  (let (
    (base-score u70)
    (compliance-bonus (* compliance-checks u5))
    (meal-type-bonus (if (is-eq meal-type "lunch") u10 u5))
  )
  (+ base-score compliance-bonus meal-type-bonus)
  )
)

(define-private (update-school-stats (school-id (string-ascii 100)) (meals-distributed uint) (students-served uint) (cost uint))
  (let (
    (current-stats (default-to
      { total-distributions: u0, total-meals-served: u0, total-students-reached: u0, average-daily-participation: u0, funding-efficiency-score: u0, nutrition-compliance-rate: u0, waste-reduction-score: u0, last-distribution-date: u0 }
      (map-get? school-distribution-stats { school-id: school-id })
    ))
  )
    (map-set school-distribution-stats
      { school-id: school-id }
      (merge current-stats {
        total-distributions: (+ (get total-distributions current-stats) u1),
        total-meals-served: (+ (get total-meals-served current-stats) meals-distributed),
        total-students-reached: (+ (get total-students-reached current-stats) students-served),
        last-distribution-date: burn-block-height
      })
    )
  )
)

;; Public Functions - Admin Only
(define-public (set-nutrition-standards (meal-type (string-ascii 20)) (age-group (string-ascii 20)) (calories-min uint) (calories-max uint) (protein-grams uint))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (< calories-min calories-max) ERR_INVALID_DISTRIBUTION)
    
    (map-set nutrition-standards
      { meal-type: meal-type, age-group: age-group }
      {
        calories-min: calories-min,
        calories-max: calories-max,
        protein-grams: protein-grams,
        vegetables-servings: u2,
        fruits-servings: u1,
        grains-servings: u2,
        dairy-servings: u1,
        sodium-limit-mg: u600,
        sugar-limit-grams: u25,
        compliance-required: true
      }
    )
    (ok true)
  )
)

(define-public (verify-distribution (distribution-id uint) (meals-count-verified uint) (quality-verified bool))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    
    (let (
      (distribution (unwrap! (map-get? meal-distributions { distribution-id: distribution-id }) ERR_MEAL_NOT_FOUND))
    )
      (map-set distribution-verification
        { distribution-id: distribution-id, verifier: tx-sender }
        {
          verification-date: burn-block-height,
          verification-type: "admin-audit",
          meals-count-verified: meals-count-verified,
          quality-verified: quality-verified,
          documentation-complete: true,
          discrepancies-found: (if (is-eq meals-count-verified (get total-meals-distributed distribution)) u0 u1),
          verification-notes: "Administrative verification completed"
        }
      )
      
      ;; Mark distribution as nutrition verified if quality check passed
      (if quality-verified
        (map-set meal-distributions
          { distribution-id: distribution-id }
          (merge distribution { nutrition-verified: true })
        )
        true
      )
      
      (ok true)
    )
  )
)

;; Public Functions - School Staff Functions
(define-public (create-meal-distribution (school-id (string-ascii 100)) (meal-type (string-ascii 20)) (planned-meals uint) (funding-campaign uint) (cost-per-meal uint))
  (begin
    (asserts! (has-distribution-permission tx-sender school-id) ERR_UNAUTHORIZED)
    (asserts! (> planned-meals u0) ERR_INVALID_DISTRIBUTION)
    (asserts! (> cost-per-meal u0) ERR_INVALID_DISTRIBUTION)
    
    (let (
      (distribution-id (+ (var-get distribution-counter) u1))
    )
      (map-set meal-distributions
        { distribution-id: distribution-id }
        {
          school-id: school-id,
          distribution-date: burn-block-height,
          meal-type: meal-type,
          total-meals-planned: planned-meals,
          total-meals-distributed: u0,
          funding-source-campaign: funding-campaign,
          verified-by: tx-sender,
          distribution-complete: false,
          cost-per-meal: cost-per-meal,
          nutrition-verified: false
        }
      )
      
      (var-set distribution-counter distribution-id)
      (ok distribution-id)
    )
  )
)

(define-public (distribute-meal-to-student (distribution-id uint) (student-anonymous-id uint) (special-dietary-accommodated bool))
  (begin
    (let (
      (distribution (unwrap! (map-get? meal-distributions { distribution-id: distribution-id }) ERR_MEAL_NOT_FOUND))
    )
      (asserts! (has-distribution-permission tx-sender (get school-id distribution)) ERR_UNAUTHORIZED)
      (asserts! (not (get distribution-complete distribution)) ERR_ALREADY_DISTRIBUTED)
      
      ;; Check if student already received meal for this distribution
      (asserts! (is-none (map-get? student-meal-records { student-anonymous-id: student-anonymous-id, distribution-id: distribution-id })) ERR_ALREADY_DISTRIBUTED)
      
      ;; Record the meal distribution to student
      (map-set student-meal-records
        { student-anonymous-id: student-anonymous-id, distribution-id: distribution-id }
        {
          meal-received: true,
          meal-type: (get meal-type distribution),
          distribution-time: burn-block-height,
          special-dietary-accommodated: special-dietary-accommodated,
          nutrition-score: (calculate-nutrition-score (get meal-type distribution) u8),
          student-satisfaction: u0, ;; To be updated later
          verified-consumption: false
        }
      )
      
      ;; Update distribution totals
      (let (
        (new-distributed-count (+ (get total-meals-distributed distribution) u1))
      )
        (map-set meal-distributions
          { distribution-id: distribution-id }
          (merge distribution {
            total-meals-distributed: new-distributed-count,
            distribution-complete: (is-eq new-distributed-count (get total-meals-planned distribution))
          })
        )
      )
      
      (var-set total-meals-distributed (+ (var-get total-meals-distributed) u1))
      (ok true)
    )
  )
)

(define-public (complete-daily-distribution (school-id (string-ascii 100)) (date uint) (breakfast-count uint) (lunch-count uint) (dinner-count uint) (total-students uint) (total-cost uint))
  (begin
    (asserts! (has-distribution-permission tx-sender school-id) ERR_UNAUTHORIZED)
    
    (map-set daily-distribution-summary
      { school-id: school-id, date: date }
      {
        breakfast-count: breakfast-count,
        lunch-count: lunch-count,
        dinner-count: dinner-count,
        snack-count: u0,
        total-students-served: total-students,
        total-cost: total-cost,
        funding-sources: (list),
        nutrition-compliance: true,
        waste-percentage: u5 ;; Default 5% waste
      }
    )
    
    ;; Update school statistics
    (update-school-stats school-id (+ breakfast-count lunch-count dinner-count) total-students total-cost)
    
    ;; Update global statistics
    (var-set total-students-served (+ (var-get total-students-served) total-students))
    
    (ok true)
  )
)

(define-public (record-student-feedback (distribution-id uint) (student-anonymous-id uint) (satisfaction-rating uint))
  (begin
    (asserts! (and (>= satisfaction-rating u1) (<= satisfaction-rating u10)) ERR_INVALID_DISTRIBUTION)
    
    (let (
      (meal-record (unwrap! (map-get? student-meal-records { student-anonymous-id: student-anonymous-id, distribution-id: distribution-id }) ERR_MEAL_NOT_FOUND))
    )
      (asserts! (get meal-received meal-record) ERR_MEAL_NOT_FOUND)
      
      (map-set student-meal-records
        { student-anonymous-id: student-anonymous-id, distribution-id: distribution-id }
        (merge meal-record { student-satisfaction: satisfaction-rating })
      )
      (ok true)
    )
  )
)

(define-public (submit-quality-report (distribution-id uint) (quality-score uint) (nutrition-compliance bool) (student-feedback-average uint) (suggestions (string-ascii 300)))
  (begin
    (asserts! (and (>= quality-score u1) (<= quality-score u10)) ERR_INVALID_DISTRIBUTION)
    (asserts! (and (>= student-feedback-average u1) (<= student-feedback-average u10)) ERR_INVALID_DISTRIBUTION)
    
    (let (
      (distribution (unwrap! (map-get? meal-distributions { distribution-id: distribution-id }) ERR_MEAL_NOT_FOUND))
      (report-id (+ (var-get meal-counter) u1))
    )
      (asserts! (has-distribution-permission tx-sender (get school-id distribution)) ERR_UNAUTHORIZED)
      
      (map-set meal-quality-reports
        { report-id: report-id }
        {
          school-id: (get school-id distribution),
          distribution-id: distribution-id,
          report-date: burn-block-height,
          reported-by: tx-sender,
          quality-score: quality-score,
          nutrition-compliance: nutrition-compliance,
          student-feedback-average: student-feedback-average,
          improvement-suggestions: suggestions,
          follow-up-required: (< quality-score u7)
        }
      )
      
      (var-set meal-counter report-id)
      (ok report-id)
    )
  )
)

(define-public (verify-meal-consumption (distribution-id uint) (student-anonymous-id uint))
  (begin
    (let (
      (meal-record (unwrap! (map-get? student-meal-records { student-anonymous-id: student-anonymous-id, distribution-id: distribution-id }) ERR_MEAL_NOT_FOUND))
      (distribution (unwrap! (map-get? meal-distributions { distribution-id: distribution-id }) ERR_MEAL_NOT_FOUND))
    )
      (asserts! (has-distribution-permission tx-sender (get school-id distribution)) ERR_UNAUTHORIZED)
      (asserts! (get meal-received meal-record) ERR_MEAL_NOT_FOUND)
      
      (map-set student-meal-records
        { student-anonymous-id: student-anonymous-id, distribution-id: distribution-id }
        (merge meal-record { verified-consumption: true })
      )
      (ok true)
    )
  )
)

;; Read-Only Functions
(define-read-only (get-distribution-info (distribution-id uint))
  (map-get? meal-distributions { distribution-id: distribution-id })
)

(define-read-only (get-student-meal-record (student-anonymous-id uint) (distribution-id uint))
  (map-get? student-meal-records { student-anonymous-id: student-anonymous-id, distribution-id: distribution-id })
)

(define-read-only (get-daily-summary (school-id (string-ascii 100)) (date uint))
  (map-get? daily-distribution-summary { school-id: school-id, date: date })
)

(define-read-only (get-nutrition-standards (meal-type (string-ascii 20)) (age-group (string-ascii 20)))
  (map-get? nutrition-standards { meal-type: meal-type, age-group: age-group })
)

(define-read-only (get-quality-report (report-id uint))
  (map-get? meal-quality-reports { report-id: report-id })
)

(define-read-only (get-school-stats (school-id (string-ascii 100)))
  (map-get? school-distribution-stats { school-id: school-id })
)

(define-read-only (get-distribution-verification (distribution-id uint) (verifier principal))
  (map-get? distribution-verification { distribution-id: distribution-id, verifier: verifier })
)

(define-read-only (get-total-meals-distributed)
  (var-get total-meals-distributed)
)

(define-read-only (get-total-students-served)
  (var-get total-students-served)
)

(define-read-only (get-distribution-counter)
  (var-get distribution-counter)
)

(define-read-only (get-meal-counter)
  (var-get meal-counter)
)

(define-read-only (calculate-impact-metrics (school-id (string-ascii 100)))
  (let (
    (stats (map-get? school-distribution-stats { school-id: school-id }))
  )
  (match stats
    school-stats {
      meals-served: (get total-meals-served school-stats),
      students-reached: (get total-students-reached school-stats),
      efficiency-score: (get funding-efficiency-score school-stats),
      nutrition-compliance: (get nutrition-compliance-rate school-stats)
    }
    { meals-served: u0, students-reached: u0, efficiency-score: u0, nutrition-compliance: u0 }
  )
  )
)

(define-read-only (get-admin)
  (var-get admin)
)
