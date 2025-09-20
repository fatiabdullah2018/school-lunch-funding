;; School Lunch Funding - Donation Pool Contract
;; Collect and manage community donations for meal programs

;; Constants
(define-constant ERR_UNAUTHORIZED (err u700))
(define-constant ERR_INSUFFICIENT_FUNDS (err u701))
(define-constant ERR_INVALID_AMOUNT (err u702))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u703))
(define-constant ERR_CAMPAIGN_ENDED (err u704))
(define-constant ERR_ALREADY_DISTRIBUTED (err u705))
(define-constant ERR_INVALID_SCHOOL (err u706))
(define-constant MIN_DONATION_AMOUNT u1000000) ;; 1 STX in microSTX
(define-constant CAMPAIGN_DURATION_BLOCKS u10080) ;; Approximately 1 week
(define-constant ADMIN_FEE_PERCENT u2) ;; 2% admin fee

;; Data Variables
(define-data-var campaign-counter uint u0)
(define-data-var total-donations-received uint u0)
(define-data-var total-meals-funded uint u0)
(define-data-var admin principal tx-sender)
(define-data-var meal-cost-per-student uint u5000000) ;; 5 STX per meal

;; Data Maps
(define-map donation-campaigns
  { campaign-id: uint }
  {
    school-id: (string-ascii 100),
    target-amount: uint,
    current-amount: uint,
    start-block: uint,
    end-block: uint,
    active: bool,
    description: (string-ascii 500),
    created-by: principal,
    students-count: uint,
    meals-per-day: uint,
    duration-days: uint,
    distributed: bool,
    distribution-date: uint
  }
)

(define-map donations
  { donor: principal, campaign-id: uint, donation-id: uint }
  {
    amount: uint,
    donation-date: uint,
    anonymous: bool,
    message: (string-ascii 200),
    refunded: bool,
    tax-deductible: bool
  }
)

(define-map donor-profiles
  { donor: principal }
  {
    total-donated: uint,
    donations-count: uint,
    favorite-schools: (list 10 (string-ascii 100)),
    first-donation: uint,
    last-donation: uint,
    anonymous-by-default: bool,
    notification-preferences: uint,
    tax-id-provided: bool
  }
)

(define-map school-profiles
  { school-id: (string-ascii 100) }
  {
    name: (string-ascii 200),
    contact-info: (string-ascii 300),
    verification-status: bool,
    total-students: uint,
    eligible-students: uint,
    campaigns-created: uint,
    total-funds-received: uint,
    last-campaign-date: uint,
    meal-program-details: (string-ascii 400)
  }
)

(define-map campaign-milestones
  { campaign-id: uint, milestone-percent: uint }
  {
    reached: bool,
    reached-date: uint,
    celebration-message: (string-ascii 200),
    donor-count-at-milestone: uint
  }
)

(define-map emergency-funds
  { school-id: (string-ascii 100) }
  {
    available-amount: uint,
    last-used: uint,
    usage-count: uint,
    replenishment-needed: bool
  }
)

(define-map donation-matching
  { matcher: principal, campaign-id: uint }
  {
    match-ratio: uint,
    max-match-amount: uint,
    current-matched: uint,
    active: bool,
    match-start: uint,
    match-end: uint
  }
)

;; Private Functions
(define-private (is-admin (user principal))
  (is-eq user (var-get admin))
)

(define-private (calculate-admin-fee (amount uint))
  (/ (* amount ADMIN_FEE_PERCENT) u100)
)

(define-private (calculate-net-donation (amount uint))
  (- amount (calculate-admin-fee amount))
)

(define-private (update-campaign-milestones (campaign-id uint) (new-amount uint))
  (let (
    (campaign (unwrap-panic (map-get? donation-campaigns { campaign-id: campaign-id })))
    (target (get target-amount campaign))
    (percentage (if (> target u0) (/ (* new-amount u100) target) u0))
  )
    ;; Check and update 25% milestone
    (if (and (>= percentage u25) (not (default-to true (get reached (map-get? campaign-milestones { campaign-id: campaign-id, milestone-percent: u25 })))))
      (map-set campaign-milestones
        { campaign-id: campaign-id, milestone-percent: u25 }
        {
          reached: true,
          reached-date: burn-block-height,
          celebration-message: "Quarter way to our goal! Thank you for your support!",
          donor-count-at-milestone: u0
        }
      )
      true
    )
    
    ;; Check and update 50% milestone
    (if (and (>= percentage u50) (not (default-to true (get reached (map-get? campaign-milestones { campaign-id: campaign-id, milestone-percent: u50 })))))
      (map-set campaign-milestones
        { campaign-id: campaign-id, milestone-percent: u50 }
        {
          reached: true,
          reached-date: burn-block-height,
          celebration-message: "Halfway there! Amazing community support!",
          donor-count-at-milestone: u0
        }
      )
      true
    )
    
    ;; Check and update 100% milestone
    (if (and (>= percentage u100) (not (default-to true (get reached (map-get? campaign-milestones { campaign-id: campaign-id, milestone-percent: u100 })))))
      (map-set campaign-milestones
        { campaign-id: campaign-id, milestone-percent: u100 }
        {
          reached: true,
          reached-date: burn-block-height,
          celebration-message: "Goal reached! Students will receive nutritious meals thanks to you!",
          donor-count-at-milestone: u0
        }
      )
      true
    )
  )
)

;; Public Functions - Admin Only
(define-public (register-school (school-id (string-ascii 100)) (name (string-ascii 200)) (contact-info (string-ascii 300)) (total-students uint) (eligible-students uint) (meal-program-details (string-ascii 400)))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> total-students u0) ERR_INVALID_AMOUNT)
    (asserts! (<= eligible-students total-students) ERR_INVALID_AMOUNT)
    
    (map-set school-profiles
      { school-id: school-id }
      {
        name: name,
        contact-info: contact-info,
        verification-status: true,
        total-students: total-students,
        eligible-students: eligible-students,
        campaigns-created: u0,
        total-funds-received: u0,
        last-campaign-date: u0,
        meal-program-details: meal-program-details
      }
    )
    (ok true)
  )
)

(define-public (verify-school (school-id (string-ascii 100)))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    
    (let (
      (school (unwrap! (map-get? school-profiles { school-id: school-id }) ERR_INVALID_SCHOOL))
    )
      (map-set school-profiles
        { school-id: school-id }
        (merge school { verification-status: true })
      )
      (ok true)
    )
  )
)

(define-public (set-meal-cost (new-cost uint))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> new-cost u0) ERR_INVALID_AMOUNT)
    (var-set meal-cost-per-student new-cost)
    (ok true)
  )
)

(define-public (distribute-funds (campaign-id uint))
  (begin
    (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
    
    (let (
      (campaign (unwrap! (map-get? donation-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
    )
      (asserts! (not (get distributed campaign)) ERR_ALREADY_DISTRIBUTED)
      (asserts! (> (get current-amount campaign) u0) ERR_INSUFFICIENT_FUNDS)
      
      ;; Calculate meals that can be funded
      (let (
        (total-available (get current-amount campaign))
        (meals-funded (/ total-available (var-get meal-cost-per-student)))
      )
        ;; Mark as distributed
        (map-set donation-campaigns
          { campaign-id: campaign-id }
          (merge campaign {
            distributed: true,
            distribution-date: burn-block-height
          })
        )
        
        ;; Update totals
        (var-set total-meals-funded (+ (var-get total-meals-funded) meals-funded))
        
        ;; Update school profile
        (let (
          (school (unwrap-panic (map-get? school-profiles { school-id: (get school-id campaign) })))
        )
          (map-set school-profiles
            { school-id: (get school-id campaign) }
            (merge school { total-funds-received: (+ (get total-funds-received school) total-available) })
          )
        )
        
        (ok meals-funded)
      )
    )
  )
)

;; Public Functions - School Functions
(define-public (create-campaign (school-id (string-ascii 100)) (target-amount uint) (description (string-ascii 500)) (students-count uint) (meals-per-day uint) (duration-days uint))
  (begin
    ;; Verify school exists and is verified
    (let (
      (school (unwrap! (map-get? school-profiles { school-id: school-id }) ERR_INVALID_SCHOOL))
    )
      (asserts! (get verification-status school) ERR_UNAUTHORIZED)
      (asserts! (> target-amount u0) ERR_INVALID_AMOUNT)
      (asserts! (> students-count u0) ERR_INVALID_AMOUNT)
      
      (let (
        (campaign-id (+ (var-get campaign-counter) u1))
        (end-block (+ burn-block-height CAMPAIGN_DURATION_BLOCKS))
      )
        ;; Create campaign
        (map-set donation-campaigns
          { campaign-id: campaign-id }
          {
            school-id: school-id,
            target-amount: target-amount,
            current-amount: u0,
            start-block: burn-block-height,
            end-block: end-block,
            active: true,
            description: description,
            created-by: tx-sender,
            students-count: students-count,
            meals-per-day: meals-per-day,
            duration-days: duration-days,
            distributed: false,
            distribution-date: u0
          }
        )
        
        ;; Update school profile
        (map-set school-profiles
          { school-id: school-id }
          (merge school {
            campaigns-created: (+ (get campaigns-created school) u1),
            last-campaign-date: burn-block-height
          })
        )
        
        (var-set campaign-counter campaign-id)
        (ok campaign-id)
      )
    )
  )
)

;; Public Functions - Donor Functions
(define-public (create-donor-profile (favorite-schools (list 10 (string-ascii 100))) (anonymous-by-default bool) (tax-id-provided bool))
  (begin
    (map-set donor-profiles
      { donor: tx-sender }
      {
        total-donated: u0,
        donations-count: u0,
        favorite-schools: favorite-schools,
        first-donation: u0,
        last-donation: u0,
        anonymous-by-default: anonymous-by-default,
        notification-preferences: u7, ;; Default: all notifications
        tax-id-provided: tax-id-provided
      }
    )
    (ok true)
  )
)

(define-public (donate-to-campaign (campaign-id uint) (amount uint) (anonymous bool) (message (string-ascii 200)))
  (begin
    (asserts! (>= amount MIN_DONATION_AMOUNT) ERR_INVALID_AMOUNT)
    
    (let (
      (campaign (unwrap! (map-get? donation-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
    )
      (asserts! (get active campaign) ERR_CAMPAIGN_ENDED)
      (asserts! (<= burn-block-height (get end-block campaign)) ERR_CAMPAIGN_ENDED)
      
      ;; Transfer STX to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Calculate net donation after admin fee
      (let (
        (net-donation (calculate-net-donation amount))
        (donation-id (+ (get donations-count (default-to { total-donated: u0, donations-count: u0, favorite-schools: (list), first-donation: u0, last-donation: u0, anonymous-by-default: false, notification-preferences: u0, tax-id-provided: false } (map-get? donor-profiles { donor: tx-sender }))) u1))
      )
        ;; Record donation
        (map-set donations
          { donor: tx-sender, campaign-id: campaign-id, donation-id: donation-id }
          {
            amount: net-donation,
            donation-date: burn-block-height,
            anonymous: anonymous,
            message: message,
            refunded: false,
            tax-deductible: true
          }
        )
        
        ;; Update campaign
        (let (
          (new-amount (+ (get current-amount campaign) net-donation))
        )
          (map-set donation-campaigns
            { campaign-id: campaign-id }
            (merge campaign { current-amount: new-amount })
          )
          
          ;; Update milestones
          (update-campaign-milestones campaign-id new-amount)
        )
        
        ;; Update donor profile
        (let (
          (donor-profile (default-to
            { total-donated: u0, donations-count: u0, favorite-schools: (list), first-donation: burn-block-height, last-donation: u0, anonymous-by-default: false, notification-preferences: u0, tax-id-provided: false }
            (map-get? donor-profiles { donor: tx-sender })
          ))
        )
          (map-set donor-profiles
            { donor: tx-sender }
            (merge donor-profile {
              total-donated: (+ (get total-donated donor-profile) net-donation),
              donations-count: (+ (get donations-count donor-profile) u1),
              last-donation: burn-block-height,
              first-donation: (if (is-eq (get donations-count donor-profile) u0) burn-block-height (get first-donation donor-profile))
            })
          )
        )
        
        (var-set total-donations-received (+ (var-get total-donations-received) net-donation))
        (ok net-donation)
      )
    )
  )
)

(define-public (setup-donation-matching (campaign-id uint) (match-ratio uint) (max-match-amount uint))
  (begin
    (asserts! (> match-ratio u0) ERR_INVALID_AMOUNT)
    (asserts! (> max-match-amount u0) ERR_INVALID_AMOUNT)
    
    (let (
      (campaign (unwrap! (map-get? donation-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
    )
      (asserts! (get active campaign) ERR_CAMPAIGN_ENDED)
      
      ;; Transfer matching funds to contract
      (try! (stx-transfer? max-match-amount tx-sender (as-contract tx-sender)))
      
      (map-set donation-matching
        { matcher: tx-sender, campaign-id: campaign-id }
        {
          match-ratio: match-ratio,
          max-match-amount: max-match-amount,
          current-matched: u0,
          active: true,
          match-start: burn-block-height,
          match-end: (get end-block campaign)
        }
      )
      (ok true)
    )
  )
)

;; Read-Only Functions
(define-read-only (get-campaign-info (campaign-id uint))
  (map-get? donation-campaigns { campaign-id: campaign-id })
)

(define-read-only (get-donation-info (donor principal) (campaign-id uint) (donation-id uint))
  (map-get? donations { donor: donor, campaign-id: campaign-id, donation-id: donation-id })
)

(define-read-only (get-donor-profile (donor principal))
  (map-get? donor-profiles { donor: donor })
)

(define-read-only (get-school-profile (school-id (string-ascii 100)))
  (map-get? school-profiles { school-id: school-id })
)

(define-read-only (get-campaign-milestone (campaign-id uint) (milestone-percent uint))
  (map-get? campaign-milestones { campaign-id: campaign-id, milestone-percent: milestone-percent })
)

(define-read-only (get-emergency-funds (school-id (string-ascii 100)))
  (map-get? emergency-funds { school-id: school-id })
)

(define-read-only (get-donation-matching (matcher principal) (campaign-id uint))
  (map-get? donation-matching { matcher: matcher, campaign-id: campaign-id })
)

(define-read-only (get-total-donations)
  (var-get total-donations-received)
)

(define-read-only (get-total-meals-funded)
  (var-get total-meals-funded)
)

(define-read-only (get-campaign-counter)
  (var-get campaign-counter)
)

(define-read-only (get-meal-cost)
  (var-get meal-cost-per-student)
)

(define-read-only (calculate-meals-from-amount (amount uint))
  (/ amount (var-get meal-cost-per-student))
)

(define-read-only (get-admin)
  (var-get admin)
)
