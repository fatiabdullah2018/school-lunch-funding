;; School Lunch Funding - Student Verification Contract
;; Verify eligible students while maintaining privacy

;; Constants
(define-constant ERR_UNAUTHORIZED (err u800))
(define-constant ERR_STUDENT_NOT_FOUND (err u801))
(define-constant ERR_ALREADY_VERIFIED (err u802))
(define-constant ERR_VERIFICATION_EXPIRED (err u803))
(define-constant ERR_INVALID_SCHOOL (err u804))
(define-constant ERR_INSUFFICIENT_DOCUMENTATION (err u805))
(define-constant ERR_PRIVACY_VIOLATION (err u806))
(define-constant VERIFICATION_PERIOD_BLOCKS u4320) ;; Approximately 1 month
(define-constant MAX_STUDENTS_PER_SCHOOL u1000)
(define-constant PRIVACY_HASH_LENGTH u64)

;; Data Variables
(define-data-var student-counter uint u0)
(define-data-var verification-counter uint u0)
(define-data-var admin principal tx-sender)
(define-data-var total-verified-students uint u0)

;; Data Maps
(define-map student-records
  { student-hash: (buff 64) }
  {
    school-id: (string-ascii 100),
    eligibility-level: uint,
    verification-date: uint,
    expiry-date: uint,
    verified-by: principal,
    active: bool,
    documentation-score: uint,
    need-assessment: uint,
    family-size: uint,
    special-dietary-needs: bool,
    anonymous-id: uint
  }
)

(define-map school-verification-stats
  { school-id: (string-ascii 100) }
  {
    total-students-verified: uint,
    pending-verifications: uint,
    verification-rate: uint,
    last-verification-date: uint,
    authorized-verifiers: (list 10 principal),
    verification-standards: uint,
    privacy-compliance: bool
  }
)

(define-map verification-requests
  { request-id: uint }
  {
    student-hash: (buff 64),
    school-id: (string-ascii 100),
    submitted-by: principal,
    request-date: uint,
    status: (string-ascii 20),
    documentation-provided: bool,
    privacy-consent: bool,
    urgency-level: uint,
    review-notes: (string-ascii 300)
  }
)

(define-map eligibility-criteria
  { school-id: (string-ascii 100), criteria-type: (string-ascii 50) }
  {
    threshold-value: uint,
    weight-factor: uint,
    documentation-required: (string-ascii 200),
    verification-method: (string-ascii 100),
    privacy-level: uint,
    active: bool
  }
)

(define-map privacy-settings
  { student-hash: (buff 64) }
  {
    data-sharing-consent: bool,
    reporting-consent: bool,
    contact-consent: bool,
    photo-consent: bool,
    third-party-sharing: bool,
    retention-period: uint,
    deletion-requested: bool
  }
)

(define-map verification-audit-log
  { audit-id: uint }
  {
    action: (string-ascii 50),
    performer: principal,
    student-hash: (buff 64),
    timestamp: uint,
    reason: (string-ascii 200),
    privacy-compliant: bool,
    school-id: (string-ascii 100)
  }
)

(define-map school-staff-permissions
  { staff-member: principal, school-id: (string-ascii 100) }
  {
    permission-level: uint,
    can-verify-students: bool,
    can-view-reports: bool,
    can-modify-criteria: bool,
    granted-date: uint,
    granted-by: principal,
    active: bool
  }
)

;; Private Functions
(define-private (is-admin (user principal))
  (is-eq user (var-get admin))
)

(define-private (has-school-permission (staff principal) (school-id (string-ascii 100)))
  (let (
    (permission (map-get? school-staff-permissions { staff-member: staff, school-id: school-id }))
  )
  (match permission
    perm-data (and (get active perm-data) (get can-verify-students perm-data))
    false
  )
  )
)

(define-private (generate-anonymous-id)
  (+ (var-get student-counter) u1)
)

(define-private (calculate-eligibility-score (family-size uint) (documentation-score uint) (need-assessment uint))
  (let (
    (family-weight (* family-size u10))
    (doc-weight (* documentation-score u15))
    (need-weight (* need-assessment u25))
    (base-score u50)
  )
  (+ base-score family-weight doc-weight need-weight)
  )
)

(define-private (log-verification-action (action (string-ascii 50)) (student-hash (buff 64)) (reason (string-ascii 200)) (school-id (string-ascii 100)))
  (let (
    (audit-id (+ (var-get verification-counter) u1))
  )
    (map-set verification-audit-log
      { audit-id: audit-id }
      {
        action: action,
        performer: tx-sender,
        student-hash: student-hash,
        timestamp: burn-block-height,
        reason: reason,
        privacy-compliant: true,
        school-id: school-id
      }
    )
    (var-set verification-counter audit-id)
  )
)

;; Public Functions - Admin Only
(define-public (register-school-staff (staff-member principal) (school-id (string-ascii 100)) (permission-level uint))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (and (>= permission-level u1) (<= permission-level u5)) ERR_UNAUTHORIZED)
    
    (map-set school-staff-permissions
      { staff-member: staff-member, school-id: school-id }
      {
        permission-level: permission-level,
        can-verify-students: (>= permission-level u2),
        can-view-reports: (>= permission-level u1),
        can-modify-criteria: (>= permission-level u4),
        granted-date: burn-block-height,
        granted-by: tx-sender,
        active: true
      }
    )
    (ok true)
  )
)

(define-public (set-eligibility-criteria (school-id (string-ascii 100)) (criteria-type (string-ascii 50)) (threshold-value uint) (weight-factor uint) (documentation-required (string-ascii 200)))
  (begin
    (asserts! (or (is-admin tx-sender) (has-school-permission tx-sender school-id)) ERR_UNAUTHORIZED)
    (asserts! (> threshold-value u0) ERR_UNAUTHORIZED)
    
    (map-set eligibility-criteria
      { school-id: school-id, criteria-type: criteria-type }
      {
        threshold-value: threshold-value,
        weight-factor: weight-factor,
        documentation-required: documentation-required,
        verification-method: "document-review",
        privacy-level: u3,
        active: true
      }
    )
    (ok true)
  )
)

;; Public Functions - School Staff Functions
(define-public (submit-verification-request (student-hash (buff 64)) (school-id (string-ascii 100)) (documentation-provided bool) (privacy-consent bool) (urgency-level uint))
  (begin
    (asserts! (has-school-permission tx-sender school-id) ERR_UNAUTHORIZED)
    (asserts! (and (>= urgency-level u1) (<= urgency-level u5)) ERR_UNAUTHORIZED)
    (asserts! privacy-consent ERR_PRIVACY_VIOLATION)
    
    (let (
      (request-id (+ (var-get verification-counter) u1))
    )
      (map-set verification-requests
        { request-id: request-id }
        {
          student-hash: student-hash,
          school-id: school-id,
          submitted-by: tx-sender,
          request-date: burn-block-height,
          status: "pending",
          documentation-provided: documentation-provided,
          privacy-consent: privacy-consent,
          urgency-level: urgency-level,
          review-notes: ""
        }
      )
      
      ;; Update school stats
      (let (
        (school-stats (default-to
          { total-students-verified: u0, pending-verifications: u0, verification-rate: u0, last-verification-date: u0, authorized-verifiers: (list), verification-standards: u3, privacy-compliance: true }
          (map-get? school-verification-stats { school-id: school-id })
        ))
      )
        (map-set school-verification-stats
          { school-id: school-id }
          (merge school-stats { pending-verifications: (+ (get pending-verifications school-stats) u1) })
        )
      )
      
      (var-set verification-counter request-id)
      (log-verification-action "request-submitted" student-hash "Verification request submitted" school-id)
      (ok request-id)
    )
  )
)

(define-public (verify-student (request-id uint) (family-size uint) (documentation-score uint) (need-assessment uint) (special-dietary-needs bool))
  (begin
    (let (
      (request (unwrap! (map-get? verification-requests { request-id: request-id }) ERR_STUDENT_NOT_FOUND))
    )
      (asserts! (has-school-permission tx-sender (get school-id request)) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status request) "pending") ERR_ALREADY_VERIFIED)
      (asserts! (get documentation-provided request) ERR_INSUFFICIENT_DOCUMENTATION)
      
      (let (
        (eligibility-score (calculate-eligibility-score family-size documentation-score need-assessment))
        (anonymous-id (generate-anonymous-id))
        (student-hash (get student-hash request))
        (school-id (get school-id request))
      )
        ;; Create student record
        (map-set student-records
          { student-hash: student-hash }
          {
            school-id: school-id,
            eligibility-level: eligibility-score,
            verification-date: burn-block-height,
            expiry-date: (+ burn-block-height VERIFICATION_PERIOD_BLOCKS),
            verified-by: tx-sender,
            active: true,
            documentation-score: documentation-score,
            need-assessment: need-assessment,
            family-size: family-size,
            special-dietary-needs: special-dietary-needs,
            anonymous-id: anonymous-id
          }
        )
        
        ;; Set default privacy settings
        (map-set privacy-settings
          { student-hash: student-hash }
          {
            data-sharing-consent: false,
            reporting-consent: true,
            contact-consent: false,
            photo-consent: false,
            third-party-sharing: false,
            retention-period: VERIFICATION_PERIOD_BLOCKS,
            deletion-requested: false
          }
        )
        
        ;; Update verification request status
        (map-set verification-requests
          { request-id: request-id }
          (merge request {
            status: "approved",
            review-notes: "Student verified and approved for meal program"
          })
        )
        
        ;; Update school stats
        (let (
          (school-stats (unwrap-panic (map-get? school-verification-stats { school-id: school-id })))
        )
          (map-set school-verification-stats
            { school-id: school-id }
            (merge school-stats {
              total-students-verified: (+ (get total-students-verified school-stats) u1),
              pending-verifications: (- (get pending-verifications school-stats) u1),
              last-verification-date: burn-block-height
            })
          )
        )
        
        (var-set student-counter anonymous-id)
        (var-set total-verified-students (+ (var-get total-verified-students) u1))
        (log-verification-action "student-verified" student-hash "Student successfully verified" school-id)
        (ok anonymous-id)
      )
    )
  )
)

(define-public (update-privacy-settings (student-hash (buff 64)) (data-sharing bool) (reporting-consent bool) (contact-consent bool))
  (begin
    ;; Only the original verifier or admin can update privacy settings
    (let (
      (student-record (unwrap! (map-get? student-records { student-hash: student-hash }) ERR_STUDENT_NOT_FOUND))
    )
      (asserts! (or (is-eq tx-sender (get verified-by student-record)) (is-admin tx-sender)) ERR_UNAUTHORIZED)
      
      (let (
        (current-settings (unwrap-panic (map-get? privacy-settings { student-hash: student-hash })))
      )
        (map-set privacy-settings
          { student-hash: student-hash }
          (merge current-settings {
            data-sharing-consent: data-sharing,
            reporting-consent: reporting-consent,
            contact-consent: contact-consent
          })
        )
        
        (log-verification-action "privacy-updated" student-hash "Privacy settings updated" (get school-id student-record))
        (ok true)
      )
    )
  )
)

(define-public (renew-verification (student-hash (buff 64)) (updated-documentation-score uint) (updated-need-assessment uint))
  (begin
    (let (
      (student-record (unwrap! (map-get? student-records { student-hash: student-hash }) ERR_STUDENT_NOT_FOUND))
    )
      (asserts! (has-school-permission tx-sender (get school-id student-record)) ERR_UNAUTHORIZED)
      (asserts! (get active student-record) ERR_STUDENT_NOT_FOUND)
      
      ;; Update verification with new information
      (let (
        (new-eligibility (calculate-eligibility-score (get family-size student-record) updated-documentation-score updated-need-assessment))
      )
        (map-set student-records
          { student-hash: student-hash }
          (merge student-record {
            eligibility-level: new-eligibility,
            verification-date: burn-block-height,
            expiry-date: (+ burn-block-height VERIFICATION_PERIOD_BLOCKS),
            documentation-score: updated-documentation-score,
            need-assessment: updated-need-assessment
          })
        )
        
        (log-verification-action "verification-renewed" student-hash "Student verification renewed" (get school-id student-record))
        (ok true)
      )
    )
  )
)

(define-public (deactivate-student (student-hash (buff 64)) (reason (string-ascii 200)))
  (begin
    (let (
      (student-record (unwrap! (map-get? student-records { student-hash: student-hash }) ERR_STUDENT_NOT_FOUND))
    )
      (asserts! (or (is-admin tx-sender) (has-school-permission tx-sender (get school-id student-record))) ERR_UNAUTHORIZED)
      
      (map-set student-records
        { student-hash: student-hash }
        (merge student-record { active: false })
      )
      
      (log-verification-action "student-deactivated" student-hash reason (get school-id student-record))
      (ok true)
    )
  )
)

;; Read-Only Functions
(define-read-only (get-student-record (student-hash (buff 64)))
  (map-get? student-records { student-hash: student-hash })
)

(define-read-only (get-verification-request (request-id uint))
  (map-get? verification-requests { request-id: request-id })
)

(define-read-only (get-school-stats (school-id (string-ascii 100)))
  (map-get? school-verification-stats { school-id: school-id })
)

(define-read-only (get-eligibility-criteria (school-id (string-ascii 100)) (criteria-type (string-ascii 50)))
  (map-get? eligibility-criteria { school-id: school-id, criteria-type: criteria-type })
)

(define-read-only (get-privacy-settings (student-hash (buff 64)))
  (map-get? privacy-settings { student-hash: student-hash })
)

(define-read-only (get-audit-log (audit-id uint))
  (map-get? verification-audit-log { audit-id: audit-id })
)

(define-read-only (get-staff-permissions (staff-member principal) (school-id (string-ascii 100)))
  (map-get? school-staff-permissions { staff-member: staff-member, school-id: school-id })
)

(define-read-only (check-verification-status (student-hash (buff 64)))
  (let (
    (student-record (map-get? student-records { student-hash: student-hash }))
  )
  (match student-record
    record (and (get active record) (> (get expiry-date record) burn-block-height))
    false
  )
  )
)

(define-read-only (get-anonymous-student-count (school-id (string-ascii 100)))
  (let (
    (school-stats (map-get? school-verification-stats { school-id: school-id }))
  )
  (match school-stats
    stats (get total-students-verified stats)
    u0
  )
  )
)

(define-read-only (get-total-verified-students)
  (var-get total-verified-students)
)

(define-read-only (get-student-counter)
  (var-get student-counter)
)

(define-read-only (get-verification-counter)
  (var-get verification-counter)
)

(define-read-only (get-admin)
  (var-get admin)
)
