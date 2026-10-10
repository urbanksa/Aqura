<script lang="ts">
  import { onMount } from "svelte";
  import {
    Building2,
    ExternalLink,
    FileUp,
    Fingerprint,
    Mail,
    Phone,
    UserRound,
  } from "lucide-svelte";
  import { supabase } from "$lib/utils/supabase";

  let activeTab: "onboarding" | "transfers" | "logs" = "onboarding";
  let boardingTransferLogs: Array<{
    id: number;
    event_type: "onboarding" | "transfer";
    employee_id: string;
    employee_name_en: string;
    employee_name_ar: string;
    effective_date: string;
    source_company_name: string;
    source_branch_name: string;
    destination_company_name: string;
    destination_branch_name: string;
    performed_by_name: string;
    performed_at: string;
    details: Record<string, unknown>;
  }> = [];
  let loadingBoardingTransferLogs = false;
  let boardingTransferLogsError = "";
  let companies: Array<{ id: number; name_en: string; name_ar: string }> = [];
  let nationalities: Array<{ id: string; name_en: string; name_ar: string }> =
    [];
  let insuranceCompanies: Array<{
    id: string;
    name_en: string;
    name_ar: string;
  }> = [];
  let branches: Array<{
    id: number;
    name_en: string;
    name_ar: string;
    location_en: string;
    location_ar: string;
  }> = [];
  let users: Array<{
    id: string;
    username: string;
    employee_id: string | null;
    name_en: string;
    name_ar: string;
  }> = [];
  let employeeDetails: {
    id: string;
    name_en: string;
    name_ar: string;
    whatsapp_number: string;
    email: string;
    sponsorship_status: boolean;
    sponsor_id: number | null;
    nationality_id: string | null;
    id_number: string;
    id_expiry_date: string;
    date_of_birth: string;
    work_permit_expiry_date: string;
    id_document_url: string;
    health_card_number: string;
    health_card_expiry_date: string;
    health_educational_renewal_date: string;
    health_card_document_url: string;
    driving_licence_number: string;
    driving_licence_expiry_date: string;
    driving_licence_document_url: string;
    contract_expiry_date: string;
    probation_period_expiry_date: string;
    join_date: string;
    contract_document_url: string;
    insurance_company_id: string;
    insurance_expiry_date: string;
    bank_name: string;
    iban: string;
    employment_status: string;
    biometricLinks: Array<{
      branchId: number;
      branchName: string;
      biometricId: string;
    }>;
    erpUser: {
      username: string;
      userId: string;
    } | null;
  } | null = null;
  let selectedCompanyId = "";
  let selectedBranchId = "";
  let selectedUserId = "";
  let onboardingStep: 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 = 1;
  let onboardingSponsorship: boolean | null = null;
  let selectedSponsorId = "";
  let onboardingNationalityId = "";
  let savedNationalityId = "";
  let nationalitySearch = "";
  let nationalityListOpen = false;
  let onboardingIdNumber = "";
  let savedIdNumber = "";
  let onboardingIdExpiryDate = "";
  let savedIdExpiryDate = "";
  let onboardingDateOfBirth = "";
  let savedDateOfBirth = "";
  let onboardingWorkPermitExpiryDate = "";
  let savedWorkPermitExpiryDate = "";
  let savingIdentity = false;
  let identityError = "";
  let identitySuccess = "";
  let idDocumentInput: HTMLInputElement;
  let idDocumentUrl = "";
  let uploadingIdDocument = false;
  let idDocumentError = "";
  let idDocumentSuccess = "";
  let healthCardNumber = "";
  let savedHealthCardNumber = "";
  let healthCardExpiryDate = "";
  let savedHealthCardExpiryDate = "";
  let healthEducationExpiryDate = "";
  let savedHealthEducationExpiryDate = "";
  let healthCardDocumentUrl = "";
  let healthCardDocumentInput: HTMLInputElement;
  let savingHealthCard = false;
  let uploadingHealthCardDocument = false;
  let healthCardError = "";
  let healthCardSuccess = "";
  let drivingLicenceNumber = "";
  let savedDrivingLicenceNumber = "";
  let drivingLicenceExpiryDate = "";
  let savedDrivingLicenceExpiryDate = "";
  let drivingLicenceDocumentUrl = "";
  let drivingLicenceDocumentInput: HTMLInputElement;
  let savingDrivingLicence = false;
  let uploadingDrivingLicenceDocument = false;
  let drivingLicenceError = "";
  let drivingLicenceSuccess = "";
  let contractExpiryDate = "";
  let savedContractExpiryDate = "";
  let probationPeriodExpiryDate = "";
  let savedProbationPeriodExpiryDate = "";
  let joiningDate = "";
  let savedJoiningDate = "";
  let contractDocumentUrl = "";
  let contractDocumentInput: HTMLInputElement;
  let savingContract = false;
  let uploadingContractDocument = false;
  let contractError = "";
  let contractSuccess = "";
  let selectedInsuranceCompanyId = "";
  let savedInsuranceCompanyId = "";
  let insuranceCompanySearch = "";
  let insuranceCompanyListOpen = false;
  let insuranceExpiryDate = "";
  let savedInsuranceExpiryDate = "";
  let savingInsurance = false;
  let insuranceError = "";
  let insuranceSuccess = "";
  let showCreateInsuranceCompany = false;
  let newInsuranceCompanyNameEn = "";
  let newInsuranceCompanyNameAr = "";
  let creatingInsuranceCompany = false;
  let bankName = "";
  let savedBankName = "";
  let iban = "";
  let savedIban = "";
  let savingBankDetails = false;
  let bankDetailsError = "";
  let bankDetailsSuccess = "";
  let onboardingEmploymentStatus = "";
  let savedEmploymentStatus = "";
  let employmentStatusEffectiveDate = "";
  let employmentStatusReason = "Onboarding completed";
  let savingEmploymentStatus = false;
  let employmentStatusError = "";
  let employmentStatusSuccess = "";
  let savingSponsorship = false;
  let sponsorshipError = "";
  let sponsorshipSuccess = "";
  let userSearch = "";
  let userListOpen = false;
  let loadingCompanies = false;
  let loadingBranches = false;
  let loadingUsers = false;
  let loadingEmployeeDetails = false;
  let companyError = "";
  let nationalityError = "";
  let branchError = "";
  let userError = "";
  let employeeDetailsError = "";
  let transferCompanyId = "";
  let transferBranchId = "";
  let transferBranches: Array<{
    id: number;
    name_en: string;
    name_ar: string;
    location_en: string;
    location_ar: string;
  }> = [];
  let loadingTransferBranches = false;
  let transferBranchError = "";
  let savingTransfer = false;
  let transferSaveError = "";
  let transferSaveSuccess = "";
  let transferBiometricId = "";
  let transferBiometricSearch = "";
  let transferBiometricListOpen = false;
  let loadingTransferBiometrics = false;
  let transferBiometricError = "";
  let transferBiometricCandidates: Array<{
    biometric_id: string;
    name: string;
  }> = [];
  let transferStep: 1 | 2 | 3 | 4 | 5 | 6 = 1;
  let loadingTransferClaims = false;
  let transferClaimCount = 0;
  let transferClaimsError = "";
  let processingTransferClaims = false;
  let transferClaimsProcessed = false;
  let transferClaimsSuccess = "";
  let loadingTransferPositions = false;
  let transferPositionError = "";
  let transferPositionId = "";
  let savedTransferPositionId = "";
  let savingTransferPosition = false;
  let transferPositionSuccess = "";
  let keepCurrentPosition = false;
  let currentTransferPosition: {
    id: string;
    title_en: string;
    title_ar: string;
  } | null = null;
  let transferPositionSearch = "";
  let transferPositionListOpen = false;
  let transferPositions: Array<{
    id: string;
    title_en: string;
    title_ar: string;
  }> = [];
  let loadingDefaultPositionHandoff = false;
  let defaultPositionError = "";
  let defaultPositionAssignmentCount = 0;
  let defaultReplacementUserId = "";
  let defaultReplacementSearch = "";
  let defaultReplacementListOpen = false;
  let defaultReplacementUsers: Array<{
    user_id: string;
    employee_id: string;
    name_en: string;
    name_ar: string;
    username: string;
  }> = [];
  let loadingEntryTaskHandoff = false;
  let entryTaskError = "";
  let isEntryTaskUser = false;
  let entryTaskReplacementUserId = "";
  let entryTaskReplacementSearch = "";
  let entryTaskReplacementListOpen = false;
  let entryTaskReplacementUsers: Array<{
    user_id: string;
    employee_id: string;
    name_en: string;
    name_ar: string;
    username: string;
  }> = [];
  let loadingBoxClosureHandoff = false;
  let boxClosureError = "";
  let hasSourceBoxClosurePermission = false;
  let hasAllBranchesBoxClosurePermission = false;
  let boxClosureReplacementUserId = "";
  let boxClosureReplacementSearch = "";
  let boxClosureReplacementListOpen = false;
  let boxClosureReplacementUsers: Array<{ user_id: string; employee_id: string; name_en: string; name_ar: string; username: string }> = [];

  $: normalizedUserSearch = userSearch.trim().toLowerCase();
  $: filteredUsers = users.filter(
    (user) =>
      !normalizedUserSearch ||
      (user.username || "").toLowerCase().includes(normalizedUserSearch) ||
      (user.employee_id || "").toLowerCase().includes(normalizedUserSearch) ||
      (user.name_en || "").toLowerCase().includes(normalizedUserSearch) ||
      (user.name_ar || "").toLowerCase().includes(normalizedUserSearch),
  );
  $: selectedBiometricLink =
    employeeDetails?.biometricLinks.find(
      (link) => String(link.branchId) === selectedBranchId,
    ) || null;
  $: normalizedTransferBiometricSearch = transferBiometricSearch
    .trim()
    .toLowerCase();
  $: filteredTransferBiometrics = transferBiometricCandidates.filter(
    (candidate) =>
      !normalizedTransferBiometricSearch ||
      candidate.biometric_id
        .toLowerCase()
        .includes(normalizedTransferBiometricSearch) ||
      (candidate.name || "")
        .toLowerCase()
        .includes(normalizedTransferBiometricSearch),
  );
  $: normalizedTransferPositionSearch = transferPositionSearch
    .trim()
    .toLowerCase();
  $: filteredTransferPositions = transferPositions.filter(
    (position) =>
      !normalizedTransferPositionSearch ||
      (position.title_en || "")
        .toLowerCase()
        .includes(normalizedTransferPositionSearch) ||
      (position.title_ar || "")
        .toLowerCase()
        .includes(normalizedTransferPositionSearch),
  );
  $: normalizedDefaultReplacementSearch = defaultReplacementSearch
    .trim()
    .toLowerCase();
  $: filteredDefaultReplacementUsers = defaultReplacementUsers.filter(
    (user) =>
      !normalizedDefaultReplacementSearch ||
      user.employee_id
        .toLowerCase()
        .includes(normalizedDefaultReplacementSearch) ||
      (user.name_en || "")
        .toLowerCase()
        .includes(normalizedDefaultReplacementSearch) ||
      (user.name_ar || "")
        .toLowerCase()
        .includes(normalizedDefaultReplacementSearch) ||
      (user.username || "")
        .toLowerCase()
        .includes(normalizedDefaultReplacementSearch),
  );
  $: normalizedEntryTaskReplacementSearch = entryTaskReplacementSearch
    .trim()
    .toLowerCase();
  $: filteredEntryTaskReplacementUsers = entryTaskReplacementUsers.filter(
    (user) =>
      !normalizedEntryTaskReplacementSearch ||
      user.employee_id
        .toLowerCase()
        .includes(normalizedEntryTaskReplacementSearch) ||
      (user.name_en || "")
        .toLowerCase()
        .includes(normalizedEntryTaskReplacementSearch) ||
      (user.name_ar || "")
        .toLowerCase()
        .includes(normalizedEntryTaskReplacementSearch) ||
      (user.username || "")
        .toLowerCase()
        .includes(normalizedEntryTaskReplacementSearch),
  );
  $: normalizedBoxClosureSearch = boxClosureReplacementSearch.trim().toLowerCase();
  $: filteredBoxClosureReplacementUsers = boxClosureReplacementUsers.filter((user) =>
    !normalizedBoxClosureSearch || user.employee_id.toLowerCase().includes(normalizedBoxClosureSearch) ||
    (user.name_en || "").toLowerCase().includes(normalizedBoxClosureSearch) ||
    (user.name_ar || "").toLowerCase().includes(normalizedBoxClosureSearch) ||
    (user.username || "").toLowerCase().includes(normalizedBoxClosureSearch));
  $: normalizedNationalitySearch = nationalitySearch.trim().toLowerCase();
  $: filteredNationalities = nationalities.filter(
    (nationality) =>
      !normalizedNationalitySearch ||
      (nationality.name_en || "")
        .toLowerCase()
        .includes(normalizedNationalitySearch) ||
      (nationality.name_ar || "")
        .toLowerCase()
        .includes(normalizedNationalitySearch),
  );
  $: identityChanged =
    onboardingNationalityId !== savedNationalityId ||
    onboardingIdNumber.trim() !== savedIdNumber ||
    onboardingIdExpiryDate !== savedIdExpiryDate ||
    onboardingDateOfBirth !== savedDateOfBirth ||
    (onboardingNationalityId !== "SA" &&
      onboardingWorkPermitExpiryDate !== savedWorkPermitExpiryDate);
  $: isNonSaudiEmployee =
    Boolean(onboardingNationalityId) && onboardingNationalityId !== "SA";
  $: healthCardChanged =
    healthCardNumber.trim() !== savedHealthCardNumber ||
    healthCardExpiryDate !== savedHealthCardExpiryDate ||
    healthEducationExpiryDate !== savedHealthEducationExpiryDate;
  $: drivingLicenceChanged =
    drivingLicenceNumber.trim() !== savedDrivingLicenceNumber ||
    drivingLicenceExpiryDate !== savedDrivingLicenceExpiryDate;
  $: contractChanged =
    contractExpiryDate !== savedContractExpiryDate ||
    probationPeriodExpiryDate !== savedProbationPeriodExpiryDate ||
    joiningDate !== savedJoiningDate;
  $: normalizedInsuranceCompanySearch = insuranceCompanySearch
    .trim()
    .toLowerCase();
  $: filteredInsuranceCompanies = insuranceCompanies.filter(
    (company) =>
      !normalizedInsuranceCompanySearch ||
      company.name_en
        .toLowerCase()
        .includes(normalizedInsuranceCompanySearch) ||
      company.name_ar.toLowerCase().includes(normalizedInsuranceCompanySearch),
  );
  $: insuranceChanged =
    selectedInsuranceCompanyId !== savedInsuranceCompanyId ||
    insuranceExpiryDate !== savedInsuranceExpiryDate;
  $: bankDetailsChanged =
    bankName.trim() !== savedBankName || iban.trim() !== savedIban;

  onMount(() => {
    loadCompanies();
    loadNationalities();
    loadInsuranceCompanies();
  });

  async function loadBoardingTransferLogs() {
    loadingBoardingTransferLogs = true;
    boardingTransferLogsError = "";
    const { data, error } = await supabase.rpc("get_boarding_transfer_logs");
    if (error) {
      boardingTransferLogs = [];
      boardingTransferLogsError =
        error.message || "Failed to load Boarding/Transfer logs.";
    } else {
      boardingTransferLogs = data || [];
    }
    loadingBoardingTransferLogs = false;
  }

  function formatLogDate(value: string) {
    if (!value) return "—";
    return new Intl.DateTimeFormat("en-GB", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
    }).format(new Date(`${value}T00:00:00`));
  }

  function formatLogDateTime(value: string) {
    if (!value) return "—";
    return new Intl.DateTimeFormat("en-GB", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "Asia/Riyadh",
    }).format(new Date(value));
  }

  async function loadInsuranceCompanies() {
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_insurance_companies",
    );
    if (error) {
      insuranceError = error.message || "Failed to load insurance companies.";
      insuranceCompanies = [];
    } else {
      insuranceCompanies = data || [];
      if (selectedInsuranceCompanyId) {
        insuranceCompanySearch = getInsuranceCompanyName(
          selectedInsuranceCompanyId,
        );
      }
    }
  }

  async function loadCompanies() {
    loadingCompanies = true;
    companyError = "";
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_companies",
    );

    if (error) {
      companyError = error.message || "Failed to load client companies.";
      companies = [];
    } else {
      companies = data || [];
    }
    loadingCompanies = false;
  }

  async function loadNationalities() {
    nationalityError = "";
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_nationalities",
    );
    if (error) {
      nationalityError = error.message || "Failed to load nationalities.";
      nationalities = [];
    } else {
      nationalities = data || [];
      if (onboardingNationalityId) {
        nationalitySearch = getNationalityName(onboardingNationalityId);
      }
    }
  }

  function getNationalityName(id: string) {
    const nationality = nationalities.find((item) => item.id === id);
    return nationality?.name_en || nationality?.name_ar || "";
  }

  async function handleCompanyChange() {
    selectedBranchId = "";
    resetUserSelection();
    branches = [];
    branchError = "";

    if (!selectedCompanyId) return;

    loadingBranches = true;
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_branches",
      { p_company_id: Number(selectedCompanyId) },
    );

    if (error) {
      branchError = error.message || "Failed to load active branches.";
      branches = [];
    } else {
      branches = data || [];
    }
    loadingBranches = false;
  }

  function resetUserSelection() {
    selectedUserId = "";
    onboardingStep = 1;
    onboardingSponsorship = null;
    selectedSponsorId = "";
    onboardingNationalityId = "";
    savedNationalityId = "";
    nationalitySearch = "";
    nationalityListOpen = false;
    onboardingIdNumber = "";
    savedIdNumber = "";
    onboardingIdExpiryDate = "";
    savedIdExpiryDate = "";
    onboardingDateOfBirth = "";
    savedDateOfBirth = "";
    onboardingWorkPermitExpiryDate = "";
    savedWorkPermitExpiryDate = "";
    identityError = "";
    identitySuccess = "";
    idDocumentUrl = "";
    uploadingIdDocument = false;
    idDocumentError = "";
    idDocumentSuccess = "";
    healthCardNumber = "";
    savedHealthCardNumber = "";
    healthCardExpiryDate = "";
    savedHealthCardExpiryDate = "";
    healthEducationExpiryDate = "";
    savedHealthEducationExpiryDate = "";
    healthCardDocumentUrl = "";
    savingHealthCard = false;
    uploadingHealthCardDocument = false;
    healthCardError = "";
    healthCardSuccess = "";
    drivingLicenceNumber = "";
    savedDrivingLicenceNumber = "";
    drivingLicenceExpiryDate = "";
    savedDrivingLicenceExpiryDate = "";
    drivingLicenceDocumentUrl = "";
    savingDrivingLicence = false;
    uploadingDrivingLicenceDocument = false;
    drivingLicenceError = "";
    drivingLicenceSuccess = "";
    contractExpiryDate = "";
    savedContractExpiryDate = "";
    probationPeriodExpiryDate = "";
    savedProbationPeriodExpiryDate = "";
    joiningDate = "";
    savedJoiningDate = "";
    contractDocumentUrl = "";
    savingContract = false;
    uploadingContractDocument = false;
    contractError = "";
    contractSuccess = "";
    selectedInsuranceCompanyId = "";
    savedInsuranceCompanyId = "";
    insuranceCompanySearch = "";
    insuranceCompanyListOpen = false;
    insuranceExpiryDate = "";
    savedInsuranceExpiryDate = "";
    savingInsurance = false;
    insuranceError = "";
    insuranceSuccess = "";
    bankName = "";
    savedBankName = "";
    iban = "";
    savedIban = "";
    savingBankDetails = false;
    bankDetailsError = "";
    bankDetailsSuccess = "";
    onboardingEmploymentStatus = "";
    savedEmploymentStatus = "";
    employmentStatusEffectiveDate = "";
    employmentStatusReason = "Onboarding completed";
    savingEmploymentStatus = false;
    employmentStatusError = "";
    employmentStatusSuccess = "";
    sponsorshipError = "";
    sponsorshipSuccess = "";
    userSearch = "";
    users = [];
    userListOpen = false;
    userError = "";
    employeeDetails = null;
    employeeDetailsError = "";
    loadingEmployeeDetails = false;
    resetTransferSelection();
  }

  function resetTransferSelection() {
    transferCompanyId = "";
    transferBranchId = "";
    transferBranches = [];
    loadingTransferBranches = false;
    transferBranchError = "";
    savingTransfer = false;
    transferSaveError = "";
    transferSaveSuccess = "";
    transferBiometricId = "";
    transferBiometricSearch = "";
    transferBiometricListOpen = false;
    loadingTransferBiometrics = false;
    transferBiometricError = "";
    transferBiometricCandidates = [];
    transferStep = 1;
    loadingTransferClaims = false;
    transferClaimCount = 0;
    transferClaimsError = "";
    processingTransferClaims = false;
    transferClaimsProcessed = false;
    transferClaimsSuccess = "";
    loadingTransferPositions = false;
    transferPositionError = "";
    transferPositionId = "";
    savedTransferPositionId = "";
    savingTransferPosition = false;
    transferPositionSuccess = "";
    keepCurrentPosition = false;
    currentTransferPosition = null;
    transferPositionSearch = "";
    transferPositionListOpen = false;
    transferPositions = [];
    loadingDefaultPositionHandoff = false;
    defaultPositionError = "";
    defaultPositionAssignmentCount = 0;
    defaultReplacementUserId = "";
    defaultReplacementSearch = "";
    defaultReplacementListOpen = false;
    defaultReplacementUsers = [];
    loadingEntryTaskHandoff = false;
    entryTaskError = "";
    isEntryTaskUser = false;
    entryTaskReplacementUserId = "";
    entryTaskReplacementSearch = "";
    entryTaskReplacementListOpen = false;
    entryTaskReplacementUsers = [];
    loadingBoxClosureHandoff = false;
    boxClosureError = "";
    hasSourceBoxClosurePermission = false;
    hasAllBranchesBoxClosurePermission = false;
    boxClosureReplacementUserId = "";
    boxClosureReplacementSearch = "";
    boxClosureReplacementListOpen = false;
    boxClosureReplacementUsers = [];
  }

  async function handleBranchChange() {
    resetUserSelection();
    if (!selectedBranchId) return;

    loadingUsers = true;
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_branch_users",
      { p_branch_id: Number(selectedBranchId) },
    );

    if (error) {
      userError = error.message || "Failed to load branch users.";
      users = [];
    } else {
      users = data || [];
    }
    loadingUsers = false;
  }

  async function selectUser(user: {
    id: string;
    username: string;
    employee_id: string | null;
    name_en: string;
    name_ar: string;
  }) {
    selectedUserId = user.id;
    resetTransferSelection();
    onboardingStep = 1;
    onboardingSponsorship = null;
    selectedSponsorId = "";
    sponsorshipError = "";
    sponsorshipSuccess = "";
    userSearch = user.name_en || user.name_ar || user.username;
    userListOpen = false;
    employeeDetails = null;
    employeeDetailsError = "";
    loadingEmployeeDetails = true;

    const { data: details, error } = await supabase.rpc(
      "get_boarding_transfer_employee_details",
      {
        p_user_id: user.id,
        p_branch_id: Number(selectedBranchId),
      },
    );

    if (selectedUserId !== user.id) return;

    if (error) {
      employeeDetailsError =
        error.message || "Failed to load Employee Master details.";
      loadingEmployeeDetails = false;
      return;
    }

    if (!details) {
      employeeDetailsError = "No Employee Master record found for this user.";
      loadingEmployeeDetails = false;
      return;
    }

    employeeDetails = {
      id: details.id,
      name_en: details.name_en || "",
      name_ar: details.name_ar || "",
      whatsapp_number: details.whatsapp_number || "",
      email: details.email || "",
      sponsorship_status: details.sponsorship_status === true,
      sponsor_id:
        details.sponsor_id == null ? null : Number(details.sponsor_id),
      nationality_id:
        details.nationality_id == null ? null : String(details.nationality_id),
      id_number: details.id_number || "",
      id_expiry_date: details.id_expiry_date || "",
      date_of_birth: details.date_of_birth || "",
      work_permit_expiry_date: details.work_permit_expiry_date || "",
      id_document_url: details.id_document_url || "",
      health_card_number: details.health_card_number || "",
      health_card_expiry_date: details.health_card_expiry_date || "",
      health_educational_renewal_date:
        details.health_educational_renewal_date || "",
      health_card_document_url: details.health_card_document_url || "",
      driving_licence_number: details.driving_licence_number || "",
      driving_licence_expiry_date: details.driving_licence_expiry_date || "",
      driving_licence_document_url: details.driving_licence_document_url || "",
      contract_expiry_date: details.contract_expiry_date || "",
      probation_period_expiry_date: details.probation_period_expiry_date || "",
      join_date: details.join_date || "",
      contract_document_url: details.contract_document_url || "",
      insurance_company_id: details.insurance_company_id || "",
      insurance_expiry_date: details.insurance_expiry_date || "",
      bank_name: details.bank_name || "",
      iban: details.iban || "",
      employment_status: details.employment_status || "",
      biometricLinks: details.biometric_link
        ? [
            {
              branchId: Number(details.biometric_link.branch_id),
              branchName: details.biometric_link.branch_name || "",
              biometricId: String(details.biometric_link.biometric_id || ""),
            },
          ]
        : [],
      erpUser: details.erp_user
        ? {
            username: details.erp_user.username || "",
            userId: String(details.erp_user.user_id || ""),
          }
        : null,
    };
    onboardingSponsorship = employeeDetails.sponsorship_status;
    selectedSponsorId = employeeDetails.sponsor_id
      ? String(employeeDetails.sponsor_id)
      : "";
    onboardingNationalityId = employeeDetails.nationality_id || "";
    savedNationalityId = onboardingNationalityId;
    nationalitySearch = getNationalityName(onboardingNationalityId);
    onboardingIdNumber = employeeDetails.id_number;
    savedIdNumber = onboardingIdNumber.trim();
    onboardingIdExpiryDate = employeeDetails.id_expiry_date;
    savedIdExpiryDate = onboardingIdExpiryDate;
    onboardingDateOfBirth = employeeDetails.date_of_birth;
    savedDateOfBirth = onboardingDateOfBirth;
    onboardingWorkPermitExpiryDate = employeeDetails.work_permit_expiry_date;
    savedWorkPermitExpiryDate = onboardingWorkPermitExpiryDate;
    idDocumentUrl = employeeDetails.id_document_url;
    healthCardNumber = employeeDetails.health_card_number;
    savedHealthCardNumber = healthCardNumber.trim();
    healthCardExpiryDate = employeeDetails.health_card_expiry_date;
    savedHealthCardExpiryDate = healthCardExpiryDate;
    healthEducationExpiryDate = employeeDetails.health_educational_renewal_date;
    savedHealthEducationExpiryDate = healthEducationExpiryDate;
    healthCardDocumentUrl = employeeDetails.health_card_document_url;
    drivingLicenceNumber = employeeDetails.driving_licence_number;
    savedDrivingLicenceNumber = drivingLicenceNumber.trim();
    drivingLicenceExpiryDate = employeeDetails.driving_licence_expiry_date;
    savedDrivingLicenceExpiryDate = drivingLicenceExpiryDate;
    drivingLicenceDocumentUrl = employeeDetails.driving_licence_document_url;
    contractExpiryDate = employeeDetails.contract_expiry_date;
    savedContractExpiryDate = contractExpiryDate;
    probationPeriodExpiryDate = employeeDetails.probation_period_expiry_date;
    savedProbationPeriodExpiryDate = probationPeriodExpiryDate;
    joiningDate = employeeDetails.join_date;
    savedJoiningDate = joiningDate;
    contractDocumentUrl = employeeDetails.contract_document_url;
    selectedInsuranceCompanyId = employeeDetails.insurance_company_id;
    savedInsuranceCompanyId = selectedInsuranceCompanyId;
    insuranceCompanySearch = getInsuranceCompanyName(
      selectedInsuranceCompanyId,
    );
    insuranceExpiryDate = employeeDetails.insurance_expiry_date;
    savedInsuranceExpiryDate = insuranceExpiryDate;
    bankName = employeeDetails.bank_name;
    savedBankName = bankName.trim();
    iban = employeeDetails.iban;
    savedIban = iban.trim();
    onboardingEmploymentStatus = ["Job (With Finger)", "Remote Job"].includes(
      employeeDetails.employment_status,
    )
      ? employeeDetails.employment_status
      : "";
    savedEmploymentStatus = employeeDetails.employment_status;
    employmentStatusEffectiveDate = joiningDate;
    loadingEmployeeDetails = false;
  }

  async function saveSponsorship(): Promise<boolean> {
    if (!employeeDetails || onboardingSponsorship === null) return false;
    if (onboardingSponsorship && !selectedSponsorId) {
      sponsorshipError = "Select a sponsor company.";
      return false;
    }

    savingSponsorship = true;
    sponsorshipError = "";
    sponsorshipSuccess = "";

    const { data, error } = await supabase.rpc(
      "set_boarding_transfer_sponsorship",
      {
        p_employee_id: employeeDetails.id,
        p_sponsorship_status: onboardingSponsorship,
        p_sponsor_id: onboardingSponsorship ? Number(selectedSponsorId) : null,
      },
    );

    if (error) {
      sponsorshipError = error.message || "Failed to save sponsorship.";
      savingSponsorship = false;
      return false;
    } else {
      employeeDetails = {
        ...employeeDetails,
        sponsorship_status: data?.sponsorship_status === true,
        sponsor_id: data?.sponsor_id == null ? null : Number(data.sponsor_id),
      };
      if (!onboardingSponsorship) selectedSponsorId = "";
      sponsorshipSuccess = "Sponsorship saved.";
    }
    savingSponsorship = false;
    return true;
  }

  async function goToOnboardingStep2() {
    if (await saveSponsorship()) onboardingStep = 2;
  }

  function selectNationality(nationality: {
    id: string;
    name_en: string;
    name_ar: string;
  }) {
    onboardingNationalityId = nationality.id;
    nationalitySearch = nationality.name_en || nationality.name_ar;
    nationalityListOpen = false;
    identityError = "";
    identitySuccess = "";
  }

  function closeNationalityList() {
    setTimeout(() => {
      nationalityListOpen = false;
      nationalitySearch = onboardingNationalityId
        ? getNationalityName(onboardingNationalityId)
        : "";
    }, 150);
  }

  async function saveIdentityDetails(): Promise<boolean> {
    if (!employeeDetails) return false;
    if (!identityChanged) return true;
    savingIdentity = true;
    identityError = "";
    identitySuccess = "";

    const { data, error } = await supabase.rpc(
      "set_boarding_transfer_identity_details",
      {
        p_employee_id: employeeDetails.id,
        p_nationality_id: onboardingNationalityId || null,
        p_id_number: onboardingIdNumber.trim() || null,
        p_id_expiry_date: onboardingIdExpiryDate || null,
        p_date_of_birth: onboardingDateOfBirth || null,
        p_work_permit_expiry_date: isNonSaudiEmployee
          ? onboardingWorkPermitExpiryDate || null
          : null,
      },
    );

    if (error) {
      identityError = error.message || "Failed to save identity details.";
      savingIdentity = false;
      return false;
    } else {
      onboardingNationalityId = data?.nationality_id
        ? String(data.nationality_id)
        : "";
      onboardingIdNumber = data?.id_number || "";
      onboardingIdExpiryDate = data?.id_expiry_date || "";
      onboardingDateOfBirth = data?.date_of_birth || "";
      onboardingWorkPermitExpiryDate = data?.work_permit_expiry_date || "";
      savedNationalityId = onboardingNationalityId;
      savedIdNumber = onboardingIdNumber.trim();
      savedIdExpiryDate = onboardingIdExpiryDate;
      savedDateOfBirth = onboardingDateOfBirth;
      savedWorkPermitExpiryDate = onboardingWorkPermitExpiryDate;
      nationalitySearch = getNationalityName(onboardingNationalityId);
      employeeDetails = {
        ...employeeDetails,
        nationality_id: onboardingNationalityId || null,
        id_number: onboardingIdNumber,
        id_expiry_date: onboardingIdExpiryDate,
        date_of_birth: onboardingDateOfBirth,
        work_permit_expiry_date: onboardingWorkPermitExpiryDate,
      };
      identitySuccess = "Identity details saved.";
    }
    savingIdentity = false;
    return true;
  }

  async function goToOnboardingStep3() {
    if (await saveIdentityDetails()) onboardingStep = 3;
  }

  function chooseIdDocument() {
    idDocumentInput?.click();
  }

  async function uploadIdDocument(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    input.value = "";
    if (!file || !employeeDetails || uploadingIdDocument) return;

    const allowedTypes = ["application/pdf", "image/jpeg", "image/png"];
    if (!allowedTypes.includes(file.type)) {
      idDocumentError = "Upload a PDF, JPG, or PNG file.";
      idDocumentSuccess = "";
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      idDocumentError = "The document must be 10 MB or smaller.";
      idDocumentSuccess = "";
      return;
    }

    uploadingIdDocument = true;
    idDocumentError = "";
    idDocumentSuccess = "";
    const extension = file.name.split(".").pop()?.toLowerCase() || "pdf";
    const filePath = `${employeeDetails.id}/${employeeDetails.id}-id-document-${Date.now()}.${extension}`;

    try {
      const { error: uploadError } = await supabase.storage
        .from("employee-documents")
        .upload(filePath, file, { contentType: file.type, upsert: false });
      if (uploadError) throw uploadError;

      const { data: publicUrl } = supabase.storage
        .from("employee-documents")
        .getPublicUrl(filePath);
      const documentUrl = publicUrl.publicUrl;
      const { data, error } = await supabase.rpc(
        "set_boarding_transfer_id_document",
        {
          p_employee_id: employeeDetails.id,
          p_id_document_url: documentUrl,
        },
      );
      if (error) throw error;

      idDocumentUrl = data?.id_document_url || documentUrl;
      employeeDetails = { ...employeeDetails, id_document_url: idDocumentUrl };
      idDocumentSuccess = idDocumentUrl
        ? "ID document uploaded successfully."
        : "";
    } catch (error) {
      idDocumentError =
        error instanceof Error
          ? error.message
          : "Failed to upload the ID document.";
    } finally {
      uploadingIdDocument = false;
    }
  }

  async function saveHealthCardDetails(): Promise<boolean> {
    if (!employeeDetails) return false;
    if (!healthCardChanged) return true;

    savingHealthCard = true;
    healthCardError = "";
    healthCardSuccess = "";
    const { data, error } = await supabase.rpc(
      "set_boarding_transfer_health_card_details",
      {
        p_employee_id: employeeDetails.id,
        p_health_card_number: healthCardNumber.trim() || null,
        p_health_card_expiry_date: healthCardExpiryDate || null,
        p_health_educational_renewal_date: healthEducationExpiryDate || null,
      },
    );

    if (error) {
      healthCardError = error.message || "Failed to save health card details.";
      savingHealthCard = false;
      return false;
    }

    healthCardNumber = data?.health_card_number || "";
    healthCardExpiryDate = data?.health_card_expiry_date || "";
    healthEducationExpiryDate = data?.health_educational_renewal_date || "";
    savedHealthCardNumber = healthCardNumber.trim();
    savedHealthCardExpiryDate = healthCardExpiryDate;
    savedHealthEducationExpiryDate = healthEducationExpiryDate;
    employeeDetails = {
      ...employeeDetails,
      health_card_number: healthCardNumber,
      health_card_expiry_date: healthCardExpiryDate,
      health_educational_renewal_date: healthEducationExpiryDate,
    };
    healthCardSuccess = "Health card details saved.";
    savingHealthCard = false;
    return true;
  }

  function chooseHealthCardDocument() {
    healthCardDocumentInput?.click();
  }

  async function uploadHealthCardDocument(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    input.value = "";
    if (!file || !employeeDetails || uploadingHealthCardDocument) return;

    const allowedTypes = ["application/pdf", "image/jpeg", "image/png"];
    if (!allowedTypes.includes(file.type)) {
      healthCardError = "Upload a PDF, JPG, or PNG file.";
      healthCardSuccess = "";
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      healthCardError = "The document must be 10 MB or smaller.";
      healthCardSuccess = "";
      return;
    }

    uploadingHealthCardDocument = true;
    healthCardError = "";
    healthCardSuccess = "";
    const extension = file.name.split(".").pop()?.toLowerCase() || "pdf";
    const filePath = `${employeeDetails.id}/${employeeDetails.id}-health-card-${Date.now()}.${extension}`;

    try {
      const { error: uploadError } = await supabase.storage
        .from("employee-documents")
        .upload(filePath, file, { contentType: file.type, upsert: false });
      if (uploadError) throw uploadError;

      const { data: publicUrl } = supabase.storage
        .from("employee-documents")
        .getPublicUrl(filePath);
      const documentUrl = publicUrl.publicUrl;
      const { data, error } = await supabase.rpc(
        "set_boarding_transfer_health_card_document",
        {
          p_employee_id: employeeDetails.id,
          p_health_card_document_url: documentUrl,
        },
      );
      if (error) throw error;

      healthCardDocumentUrl = data?.health_card_document_url || documentUrl;
      employeeDetails = {
        ...employeeDetails,
        health_card_document_url: healthCardDocumentUrl,
      };
      healthCardSuccess = "Health card document uploaded successfully.";
    } catch (error) {
      healthCardError =
        error instanceof Error
          ? error.message
          : "Failed to upload the health card document.";
    } finally {
      uploadingHealthCardDocument = false;
    }
  }

  async function goToOnboardingStep4() {
    if (await saveHealthCardDetails()) onboardingStep = 4;
  }

  async function saveDrivingLicenceDetails(): Promise<boolean> {
    if (!employeeDetails) return false;
    if (!drivingLicenceChanged) return true;

    savingDrivingLicence = true;
    drivingLicenceError = "";
    drivingLicenceSuccess = "";
    const { data, error } = await supabase.rpc(
      "set_boarding_transfer_driving_licence_details",
      {
        p_employee_id: employeeDetails.id,
        p_driving_licence_number: drivingLicenceNumber.trim() || null,
        p_driving_licence_expiry_date: drivingLicenceExpiryDate || null,
      },
    );

    if (error) {
      drivingLicenceError =
        error.message || "Failed to save driving licence details.";
      savingDrivingLicence = false;
      return false;
    }

    drivingLicenceNumber = data?.driving_licence_number || "";
    drivingLicenceExpiryDate = data?.driving_licence_expiry_date || "";
    savedDrivingLicenceNumber = drivingLicenceNumber.trim();
    savedDrivingLicenceExpiryDate = drivingLicenceExpiryDate;
    employeeDetails = {
      ...employeeDetails,
      driving_licence_number: drivingLicenceNumber,
      driving_licence_expiry_date: drivingLicenceExpiryDate,
    };
    drivingLicenceSuccess = "Driving licence details saved.";
    savingDrivingLicence = false;
    return true;
  }

  function chooseDrivingLicenceDocument() {
    drivingLicenceDocumentInput?.click();
  }

  async function uploadDrivingLicenceDocument(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    input.value = "";
    if (!file || !employeeDetails || uploadingDrivingLicenceDocument) return;

    const allowedTypes = ["application/pdf", "image/jpeg", "image/png"];
    if (!allowedTypes.includes(file.type)) {
      drivingLicenceError = "Upload a PDF, JPG, or PNG file.";
      drivingLicenceSuccess = "";
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      drivingLicenceError = "The document must be 10 MB or smaller.";
      drivingLicenceSuccess = "";
      return;
    }

    uploadingDrivingLicenceDocument = true;
    drivingLicenceError = "";
    drivingLicenceSuccess = "";
    const extension = file.name.split(".").pop()?.toLowerCase() || "pdf";
    const filePath = `${employeeDetails.id}/${employeeDetails.id}-driving-licence-${Date.now()}.${extension}`;

    try {
      const { error: uploadError } = await supabase.storage
        .from("employee-documents")
        .upload(filePath, file, { contentType: file.type, upsert: false });
      if (uploadError) throw uploadError;

      const { data: publicUrl } = supabase.storage
        .from("employee-documents")
        .getPublicUrl(filePath);
      const documentUrl = publicUrl.publicUrl;
      const { data, error } = await supabase.rpc(
        "set_boarding_transfer_driving_licence_document",
        {
          p_employee_id: employeeDetails.id,
          p_driving_licence_document_url: documentUrl,
        },
      );
      if (error) throw error;

      drivingLicenceDocumentUrl =
        data?.driving_licence_document_url || documentUrl;
      employeeDetails = {
        ...employeeDetails,
        driving_licence_document_url: drivingLicenceDocumentUrl,
      };
      drivingLicenceSuccess = "Driving licence document uploaded successfully.";
    } catch (error) {
      drivingLicenceError =
        error instanceof Error
          ? error.message
          : "Failed to upload the driving licence document.";
    } finally {
      uploadingDrivingLicenceDocument = false;
    }
  }

  async function goToOnboardingStep5() {
    if (await saveDrivingLicenceDetails()) onboardingStep = 5;
  }

  async function saveContractDetails(): Promise<boolean> {
    if (!employeeDetails) return false;
    if (!contractChanged) return true;

    savingContract = true;
    contractError = "";
    contractSuccess = "";
    const { data, error } = await supabase.rpc(
      "set_boarding_transfer_contract_details",
      {
        p_employee_id: employeeDetails.id,
        p_contract_expiry_date: contractExpiryDate || null,
        p_probation_period_expiry_date: probationPeriodExpiryDate || null,
        p_join_date: joiningDate || null,
      },
    );

    if (error) {
      contractError = error.message || "Failed to save contract details.";
      savingContract = false;
      return false;
    }

    contractExpiryDate = data?.contract_expiry_date || "";
    probationPeriodExpiryDate = data?.probation_period_expiry_date || "";
    joiningDate = data?.join_date || "";
    savedContractExpiryDate = contractExpiryDate;
    savedProbationPeriodExpiryDate = probationPeriodExpiryDate;
    savedJoiningDate = joiningDate;
    employeeDetails = {
      ...employeeDetails,
      contract_expiry_date: contractExpiryDate,
      probation_period_expiry_date: probationPeriodExpiryDate,
      join_date: joiningDate,
    };
    contractSuccess = "Contract details saved.";
    savingContract = false;
    return true;
  }

  function chooseContractDocument() {
    contractDocumentInput?.click();
  }

  async function uploadContractDocument(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    input.value = "";
    if (!file || !employeeDetails || uploadingContractDocument) return;

    const allowedTypes = ["application/pdf", "image/jpeg", "image/png"];
    if (!allowedTypes.includes(file.type)) {
      contractError = "Upload a PDF, JPG, or PNG file.";
      contractSuccess = "";
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      contractError = "The document must be 10 MB or smaller.";
      contractSuccess = "";
      return;
    }

    uploadingContractDocument = true;
    contractError = "";
    contractSuccess = "";
    const extension = file.name.split(".").pop()?.toLowerCase() || "pdf";
    const filePath = `${employeeDetails.id}/${employeeDetails.id}-contract-${Date.now()}.${extension}`;

    try {
      const { error: uploadError } = await supabase.storage
        .from("employee-documents")
        .upload(filePath, file, { contentType: file.type, upsert: false });
      if (uploadError) throw uploadError;

      const { data: publicUrl } = supabase.storage
        .from("employee-documents")
        .getPublicUrl(filePath);
      const documentUrl = publicUrl.publicUrl;
      const { data, error } = await supabase.rpc(
        "set_boarding_transfer_contract_document",
        {
          p_employee_id: employeeDetails.id,
          p_contract_document_url: documentUrl,
        },
      );
      if (error) throw error;

      contractDocumentUrl = data?.contract_document_url || documentUrl;
      employeeDetails = {
        ...employeeDetails,
        contract_document_url: contractDocumentUrl,
      };
      contractSuccess = "Contract document uploaded successfully.";
    } catch (error) {
      contractError =
        error instanceof Error
          ? error.message
          : "Failed to upload the contract document.";
    } finally {
      uploadingContractDocument = false;
    }
  }

  async function goToOnboardingStep6() {
    if (await saveContractDetails()) onboardingStep = 6;
  }

  function getInsuranceCompanyName(id: string) {
    const company = insuranceCompanies.find((item) => item.id === id);
    return company?.name_en || company?.name_ar || "";
  }

  function selectInsuranceCompany(company: {
    id: string;
    name_en: string;
    name_ar: string;
  }) {
    selectedInsuranceCompanyId = company.id;
    insuranceCompanySearch = company.name_en || company.name_ar;
    insuranceCompanyListOpen = false;
    insuranceError = "";
    insuranceSuccess = "";
  }

  function closeInsuranceCompanyList() {
    setTimeout(() => {
      insuranceCompanyListOpen = false;
      insuranceCompanySearch = selectedInsuranceCompanyId
        ? getInsuranceCompanyName(selectedInsuranceCompanyId)
        : "";
    }, 150);
  }

  async function saveInsuranceDetails(): Promise<boolean> {
    if (!employeeDetails) return false;
    if (!insuranceChanged) return true;

    savingInsurance = true;
    insuranceError = "";
    insuranceSuccess = "";
    const { data, error } = await supabase.rpc(
      "set_boarding_transfer_health_insurance",
      {
        p_employee_id: employeeDetails.id,
        p_insurance_company_id: selectedInsuranceCompanyId || null,
        p_insurance_expiry_date: insuranceExpiryDate || null,
      },
    );
    if (error) {
      insuranceError = error.message || "Failed to save health insurance.";
      savingInsurance = false;
      return false;
    }

    selectedInsuranceCompanyId = data?.insurance_company_id || "";
    savedInsuranceCompanyId = selectedInsuranceCompanyId;
    insuranceCompanySearch = getInsuranceCompanyName(
      selectedInsuranceCompanyId,
    );
    insuranceExpiryDate = data?.insurance_expiry_date || "";
    savedInsuranceExpiryDate = insuranceExpiryDate;
    employeeDetails = {
      ...employeeDetails,
      insurance_company_id: selectedInsuranceCompanyId,
      insurance_expiry_date: insuranceExpiryDate,
    };
    insuranceSuccess = "Health insurance saved.";
    savingInsurance = false;
    return true;
  }

  async function createInsuranceCompany() {
    if (
      !newInsuranceCompanyNameEn.trim() ||
      !newInsuranceCompanyNameAr.trim()
    ) {
      insuranceError = "Enter the company name in English and Arabic.";
      return;
    }
    creatingInsuranceCompany = true;
    insuranceError = "";
    const { data, error } = await supabase.rpc(
      "create_boarding_transfer_insurance_company",
      {
        p_name_en: newInsuranceCompanyNameEn.trim(),
        p_name_ar: newInsuranceCompanyNameAr.trim(),
      },
    );
    if (error) {
      insuranceError = error.message || "Failed to create insurance company.";
    } else {
      const company = {
        id: String(data.id),
        name_en: data.name_en || "",
        name_ar: data.name_ar || "",
      };
      insuranceCompanies = [...insuranceCompanies, company].sort((a, b) =>
        a.name_en.localeCompare(b.name_en),
      );
      selectInsuranceCompany(company);
      newInsuranceCompanyNameEn = "";
      newInsuranceCompanyNameAr = "";
      showCreateInsuranceCompany = false;
      insuranceSuccess = "Insurance company created.";
    }
    creatingInsuranceCompany = false;
  }

  async function goToOnboardingStep7() {
    if (await saveInsuranceDetails()) onboardingStep = 7;
  }

  async function saveBankDetails(): Promise<boolean> {
    if (!employeeDetails) return false;
    if (!bankDetailsChanged) return true;

    savingBankDetails = true;
    bankDetailsError = "";
    bankDetailsSuccess = "";
    const { data, error } = await supabase.rpc(
      "set_boarding_transfer_bank_details",
      {
        p_employee_id: employeeDetails.id,
        p_bank_name: bankName.trim() || null,
        p_iban: iban.trim() || null,
      },
    );
    if (error) {
      bankDetailsError = error.message || "Failed to save bank details.";
      savingBankDetails = false;
      return false;
    }

    bankName = data?.bank_name || "";
    iban = data?.iban || "";
    savedBankName = bankName.trim();
    savedIban = iban.trim();
    employeeDetails = { ...employeeDetails, bank_name: bankName, iban };
    bankDetailsSuccess = "Bank details saved.";
    savingBankDetails = false;
    return true;
  }

  async function goToOnboardingStep8() {
    if (await saveBankDetails()) {
      if (!employmentStatusEffectiveDate) {
        employmentStatusEffectiveDate = joiningDate;
      }
      onboardingStep = 8;
    }
  }

  async function saveEmploymentStatus() {
    if (!employeeDetails) return;
    if (!employmentStatusEffectiveDate) {
      employmentStatusError = "Effective Date is required.";
      return;
    }
    if (!onboardingEmploymentStatus) {
      employmentStatusError = "Select an employment status.";
      return;
    }
    if (!employmentStatusReason.trim()) {
      employmentStatusError = "Reason is required.";
      return;
    }

    savingEmploymentStatus = true;
    employmentStatusError = "";
    employmentStatusSuccess = "";
    const { data, error } = await supabase.rpc(
      "set_boarding_transfer_employee_status",
      {
        p_employee_id: employeeDetails.id,
        p_new_status: onboardingEmploymentStatus,
        p_effective_date: employmentStatusEffectiveDate,
        p_reason: employmentStatusReason.trim(),
      },
    );
    if (error) {
      employmentStatusError =
        error.message || "Failed to update employee status.";
    } else {
      onboardingEmploymentStatus = data?.status || onboardingEmploymentStatus;
      savedEmploymentStatus = onboardingEmploymentStatus;
      employeeDetails = {
        ...employeeDetails,
        employment_status: onboardingEmploymentStatus,
      };
      employmentStatusSuccess = "Employee onboarding completed.";
    }
    savingEmploymentStatus = false;
  }

  async function handleTransferCompanyChange() {
    transferStep = 1;
    transferBranchId = "";
    transferBranches = [];
    transferBranchError = "";
    transferSaveError = "";
    transferSaveSuccess = "";
    transferBiometricId = "";
    transferBiometricSearch = "";
    transferBiometricCandidates = [];
    transferBiometricError = "";
    if (!transferCompanyId) return;

    loadingTransferBranches = true;
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_branches",
      { p_company_id: Number(transferCompanyId) },
    );
    if (error) {
      transferBranchError =
        error.message || "Failed to load destination branches.";
    } else {
      transferBranches = (data || []).filter(
        (branch: { id: number }) => String(branch.id) !== selectedBranchId,
      );
    }
    loadingTransferBranches = false;
  }

  async function handleTransferBranchChange() {
    transferStep = 1;
    transferSaveError = "";
    transferSaveSuccess = "";
    transferBiometricId = "";
    transferBiometricSearch = "";
    transferBiometricCandidates = [];
    transferBiometricError = "";
    transferBiometricListOpen = false;
    if (!transferBranchId || !employeeDetails) return;

    loadingTransferBiometrics = true;
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_destination_biometrics",
      {
        p_employee_id: employeeDetails.id,
        p_branch_id: Number(transferBranchId),
      },
    );
    if (error) {
      transferBiometricError =
        error.message || "Failed to load destination biometric IDs.";
    } else {
      transferBiometricId = data?.current_biometric_id || "";
      transferBiometricCandidates = data?.candidates || [];
    }
    loadingTransferBiometrics = false;
  }

  function selectTransferBiometric(candidate: {
    biometric_id: string;
    name: string;
  }) {
    transferBiometricId = candidate.biometric_id;
    transferBiometricSearch = "";
    transferBiometricListOpen = false;
    transferBiometricError = "";
  }

  async function openTransferClaimsStep() {
    transferSaveError = "";
    transferSaveSuccess = "";
    transferClaimsError = "";
    transferClaimsProcessed = false;
    transferClaimsSuccess = "";

    if (
      !employeeDetails ||
      !selectedUserId ||
      !selectedBranchId ||
      !transferCompanyId ||
      !transferBranchId ||
      !transferBiometricId
    ) {
      transferSaveError =
        "Select an employee, destination company, branch, and biometric ID.";
      return;
    }

    loadingTransferClaims = true;
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_claim_handoff",
      {
        p_employee_id: employeeDetails.id,
        p_source_branch_id: Number(selectedBranchId),
      },
    );
    if (error) {
      transferClaimsError =
        error.message || "Failed to load product claim count.";
    } else {
      transferClaimCount = Number(data?.claim_count || 0);
      transferClaimsProcessed = transferClaimCount === 0;
      transferStep = 2;
    }
    loadingTransferClaims = false;
  }

  async function processTransferClaims() {
    transferClaimsError = "";
    transferClaimsSuccess = "";
    if (!employeeDetails || !selectedBranchId) {
      transferClaimsError = "Select an employee and source branch.";
      return;
    }

    processingTransferClaims = true;
    const { data, error } = await supabase.rpc(
      "process_boarding_transfer_claims",
      {
        p_employee_id: employeeDetails.id,
        p_source_branch_id: Number(selectedBranchId),
      },
    );
    if (error) {
      transferClaimsError =
        error.message || "Failed to move product claims to In Process.";
    } else {
      const movedCount = Number(data || 0);
      transferClaimCount = 0;
      transferClaimsProcessed = true;
      transferClaimsSuccess = `${movedCount} product claims moved to In Process.`;
    }
    processingTransferClaims = false;
  }

  async function openTransferPositionStep() {
    transferClaimsError = "";
    transferPositionError = "";
    transferPositionId = "";
    savedTransferPositionId = "";
    savingTransferPosition = false;
    transferPositionSuccess = "";
    keepCurrentPosition = false;
    currentTransferPosition = null;
    transferPositionSearch = "";
    transferPositionListOpen = false;

    if (!employeeDetails) return;

    loadingTransferPositions = true;
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_position_options",
      { p_employee_id: employeeDetails.id },
    );
    if (error) {
      transferPositionError =
        error.message || "Failed to load active positions.";
    } else {
      currentTransferPosition = data?.current_position || null;
      transferPositions = data?.positions || [];
      transferStep = 3;
    }
    loadingTransferPositions = false;
  }

  function selectTransferPosition(position: {
    id: string;
    title_en: string;
    title_ar: string;
  }) {
    transferPositionId = position.id;
    savedTransferPositionId = "";
    transferPositionSuccess = "";
    keepCurrentPosition = false;
    transferPositionSearch = position.title_en || position.title_ar;
    transferPositionListOpen = false;
    transferPositionError = "";
  }

  async function saveTransferPosition() {
    transferPositionError = "";
    transferPositionSuccess = "";
    if (!employeeDetails || !selectedUserId || !transferPositionId) {
      transferPositionError = "Select a new position.";
      return;
    }

    savingTransferPosition = true;
    const { error } = await supabase.rpc(
      "set_boarding_transfer_employee_position",
      {
        p_employee_id: employeeDetails.id,
        p_user_id: selectedUserId,
        p_new_position_id: transferPositionId,
      },
    );
    if (error) {
      transferPositionError =
        error.message || "Failed to save the employee position.";
    } else {
      savedTransferPositionId = transferPositionId;
      currentTransferPosition =
        transferPositions.find(
          (position) => position.id === transferPositionId,
        ) || currentTransferPosition;
      transferPositionSuccess = "Position saved.";
    }
    savingTransferPosition = false;
  }

  async function openDefaultPositionsStep() {
    transferPositionError = "";
    defaultPositionError = "";
    defaultReplacementUserId = "";
    defaultReplacementSearch = "";
    defaultReplacementListOpen = false;

    if (
      !keepCurrentPosition &&
      (!transferPositionId || savedTransferPositionId !== transferPositionId)
    ) {
      transferPositionError =
        "Save the new position before continuing.";
      return;
    }
    if (!selectedUserId || !selectedBranchId) return;

    loadingDefaultPositionHandoff = true;
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_default_position_handoff",
      {
        p_user_id: selectedUserId,
        p_source_branch_id: Number(selectedBranchId),
      },
    );
    if (error) {
      defaultPositionError =
        error.message || "Failed to load default-position assignments.";
    } else {
      defaultPositionAssignmentCount = Number(data?.assignment_count || 0);
      defaultReplacementUsers = data?.replacement_users || [];
      transferStep = 4;
    }
    loadingDefaultPositionHandoff = false;
  }

  function selectDefaultReplacementUser(user: {
    user_id: string;
    name_en: string;
    name_ar: string;
    username: string;
  }) {
    defaultReplacementUserId = user.user_id;
    defaultReplacementSearch = user.name_en || user.name_ar || user.username;
    defaultReplacementListOpen = false;
    defaultPositionError = "";
  }

  async function openEntryTaskStep() {
    defaultPositionError = "";
    entryTaskError = "";
    entryTaskReplacementUserId = "";
    entryTaskReplacementSearch = "";
    entryTaskReplacementListOpen = false;

    if (
      defaultPositionAssignmentCount > 0 &&
      !defaultReplacementUserId
    ) {
      defaultPositionError =
        "Select the user who will receive the default positions.";
      return;
    }
    if (!selectedUserId || !selectedBranchId) return;

    loadingEntryTaskHandoff = true;
    const { data, error } = await supabase.rpc(
      "get_boarding_transfer_entry_task_handoff",
      {
        p_user_id: selectedUserId,
        p_source_branch_id: Number(selectedBranchId),
      },
    );
    if (error) {
      entryTaskError =
        error.message || "Failed to load the Entry Task User assignment.";
    } else {
      isEntryTaskUser = Boolean(data?.is_assigned);
      entryTaskReplacementUsers = data?.replacement_users || [];
      transferStep = 5;
    }
    loadingEntryTaskHandoff = false;
  }

  function selectEntryTaskReplacementUser(user: {
    user_id: string;
    name_en: string;
    name_ar: string;
    username: string;
  }) {
    entryTaskReplacementUserId = user.user_id;
    entryTaskReplacementSearch = user.name_en || user.name_ar || user.username;
    entryTaskReplacementListOpen = false;
    entryTaskError = "";
  }

  async function openBoxClosureStep() {
    entryTaskError = "";
    boxClosureError = "";
    boxClosureReplacementUserId = "";
    boxClosureReplacementSearch = "";
    boxClosureReplacementListOpen = false;
    if (isEntryTaskUser && !entryTaskReplacementUserId) {
      entryTaskError = "Select the replacement Entry Task User.";
      return;
    }
    if (!selectedUserId || !selectedBranchId) return;
    loadingBoxClosureHandoff = true;
    const { data, error } = await supabase.rpc("get_boarding_transfer_box_closure_handoff", {
      p_user_id: selectedUserId,
      p_source_branch_id: Number(selectedBranchId),
    });
    if (error) {
      boxClosureError = error.message || "Failed to load Complete Box Closure permission.";
    } else {
      hasSourceBoxClosurePermission = Boolean(data?.has_source_branch_permission);
      hasAllBranchesBoxClosurePermission = Boolean(data?.has_all_branches_permission);
      boxClosureReplacementUsers = data?.replacement_users || [];
      transferStep = 6;
    }
    loadingBoxClosureHandoff = false;
  }

  function selectBoxClosureReplacementUser(user: { user_id: string; name_en: string; name_ar: string; username: string }) {
    boxClosureReplacementUserId = user.user_id;
    boxClosureReplacementSearch = user.name_en || user.name_ar || user.username;
    boxClosureReplacementListOpen = false;
    boxClosureError = "";
  }

  async function saveEmployeeTransfer() {
    transferSaveError = "";
    transferSaveSuccess = "";

    if (
      !employeeDetails ||
      !selectedUserId ||
      !transferCompanyId ||
      !transferBranchId ||
      !transferBiometricId ||
      (!keepCurrentPosition && !transferPositionId) ||
      (defaultPositionAssignmentCount > 0 && !defaultReplacementUserId) ||
      (isEntryTaskUser && !entryTaskReplacementUserId) ||
      (hasSourceBoxClosurePermission && !boxClosureReplacementUserId)
    ) {
      transferSaveError =
        hasSourceBoxClosurePermission && !boxClosureReplacementUserId
          ? "Select the Complete Box Closure replacement user."
          : isEntryTaskUser && !entryTaskReplacementUserId
          ? "Select the replacement Entry Task User."
          : defaultPositionAssignmentCount > 0 && !defaultReplacementUserId
          ? "Select the user who will receive the default positions."
          : !keepCurrentPosition && !transferPositionId
          ? "Keep the current position or select a new position."
          : "Select an employee, destination company, branch, and biometric ID.";
      return;
    }

    savingTransfer = true;
    const { error } = await supabase.rpc(
      "complete_boarding_transfer",
      {
        p_employee_id: employeeDetails.id,
        p_user_id: selectedUserId,
        p_source_branch_id: Number(selectedBranchId),
        p_destination_company_id: Number(transferCompanyId),
        p_destination_branch_id: Number(transferBranchId),
        p_biometric_id: transferBiometricId,
        p_replacement_employee_id: null,
        p_new_position_id: keepCurrentPosition ? null : transferPositionId,
        p_default_replacement_user_id:
          defaultPositionAssignmentCount > 0
            ? defaultReplacementUserId
            : null,
        p_entry_task_replacement_user_id: isEntryTaskUser
          ? entryTaskReplacementUserId
          : null,
        p_box_closure_replacement_user_id: hasSourceBoxClosurePermission
          ? boxClosureReplacementUserId
          : null,
      },
    );

    if (error) {
      transferSaveError = error.message || "Failed to save employee transfer.";
    } else {
      transferSaveSuccess =
        "Transfer saved. The user's connected branch and Employee Master's current branch were updated.";
    }
    savingTransfer = false;
  }

  function closeUserList() {
    setTimeout(() => (userListOpen = false), 150);
  }
</script>

<div class="flex h-full w-full flex-col bg-slate-50">
  <div class="flex gap-2 border-b border-slate-200 bg-white px-6 pt-5">
    <button
      type="button"
      class="rounded-t-xl px-6 py-3 text-sm font-bold transition-colors {activeTab ===
      'onboarding'
        ? 'bg-emerald-600 text-white'
        : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}"
      on:click={() => (activeTab = "onboarding")}
    >
      Onboarding
    </button>
    <button
      type="button"
      class="rounded-t-xl px-6 py-3 text-sm font-bold transition-colors {activeTab ===
      'transfers'
        ? 'bg-emerald-600 text-white'
        : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}"
      on:click={() => (activeTab = "transfers")}
    >
      Transfers
    </button>
    <button
      type="button"
      class="rounded-t-xl px-6 py-3 text-sm font-bold transition-colors {activeTab ===
      'logs'
        ? 'bg-emerald-600 text-white'
        : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}"
      on:click={() => {
        activeTab = "logs";
        loadBoardingTransferLogs();
      }}
    >
      Logs
    </button>
  </div>

  {#if activeTab === "logs"}
    <div class="min-h-0 flex-1 overflow-auto bg-slate-50 p-6">
      <div class="rounded-2xl border border-slate-200 bg-white shadow-sm">
        <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-5 py-4">
          <div>
            <h2 class="text-lg font-bold text-slate-900">Boarding/Transfer Logs</h2>
            <p class="mt-1 text-sm text-slate-500">Onboarding completions and employee branch transfers.</p>
          </div>
          <button
            type="button"
            on:click={loadBoardingTransferLogs}
            disabled={loadingBoardingTransferLogs}
            class="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-bold text-slate-700 hover:bg-slate-100 disabled:opacity-50"
          >
            {loadingBoardingTransferLogs ? "Loading..." : "Refresh"}
          </button>
        </div>

        {#if boardingTransferLogsError}
          <p class="m-5 rounded-xl bg-red-50 px-4 py-3 text-sm font-medium text-red-700">{boardingTransferLogsError}</p>
        {:else if loadingBoardingTransferLogs}
          <p class="p-8 text-center text-sm text-slate-500">Loading logs...</p>
        {:else if boardingTransferLogs.length === 0}
          <p class="p-8 text-center text-sm text-slate-500">No Boarding/Transfer logs found.</p>
        {:else}
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-slate-200 text-sm">
              <thead class="bg-slate-50 text-left text-xs font-bold uppercase tracking-wide text-slate-500">
                <tr>
                  <th class="px-4 py-3">Type</th>
                  <th class="px-4 py-3">Employee</th>
                  <th class="px-4 py-3">From</th>
                  <th class="px-4 py-3">To</th>
                  <th class="px-4 py-3">Effective Date</th>
                  <th class="px-4 py-3">Performed By</th>
                  <th class="px-4 py-3">Action Time</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100 bg-white">
                {#each boardingTransferLogs as log (log.id)}
                  <tr class="hover:bg-slate-50">
                    <td class="whitespace-nowrap px-4 py-3">
                      <span class="rounded-full px-3 py-1 text-xs font-bold {log.event_type === 'transfer' ? 'bg-blue-50 text-blue-700' : 'bg-emerald-50 text-emerald-700'}">
                        {log.event_type === "transfer" ? "Transfer" : "Onboarding"}
                      </span>
                    </td>
                    <td class="px-4 py-3">
                      <p class="font-bold text-slate-900">{log.employee_name_en || log.employee_id}</p>
                      {#if log.employee_name_ar}<p class="text-xs text-slate-500" dir="rtl">{log.employee_name_ar}</p>{/if}
                      <p class="text-xs text-slate-400">{log.employee_id}</p>
                    </td>
                    <td class="px-4 py-3 text-slate-600">
                      {log.source_branch_name || "—"}
                      {#if log.source_company_name}<p class="text-xs text-slate-400">{log.source_company_name}</p>{/if}
                    </td>
                    <td class="px-4 py-3 text-slate-600">
                      {log.destination_branch_name || "—"}
                      {#if log.destination_company_name}<p class="text-xs text-slate-400">{log.destination_company_name}</p>{/if}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-slate-600">{formatLogDate(log.effective_date)}</td>
                    <td class="px-4 py-3 font-medium text-slate-700">{log.performed_by_name || "Unknown"}</td>
                    <td class="whitespace-nowrap px-4 py-3 text-slate-600">{formatLogDateTime(log.performed_at)}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        {/if}
      </div>
    </div>
  {:else}
  <div class="flex min-h-0 flex-1 flex-col bg-white lg:flex-row">
    <div
      class="w-full overflow-y-auto border-b border-slate-200 bg-white px-6 py-5 lg:w-[30%] lg:border-b-0 lg:border-r"
    >
      <div class="grid grid-cols-1 gap-5">
        <div>
          <label
            for="client-company"
            class="mb-2 block text-sm font-bold text-slate-700"
            >Select Client Company</label
          >
          <select
            id="client-company"
            bind:value={selectedCompanyId}
            on:change={handleCompanyChange}
            disabled={loadingCompanies}
            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200 disabled:bg-slate-100"
          >
            <option value=""
              >{loadingCompanies
                ? "Loading companies..."
                : "Select a company"}</option
            >
            {#each companies as company (company.id)}
              <option value={String(company.id)}
                >{company.name_en || company.name_ar}</option
              >
            {/each}
          </select>
          {#if companyError}
            <p class="mt-2 text-sm text-red-600">{companyError}</p>
          {/if}
        </div>

        <div>
          <label
            for="client-branch"
            class="mb-2 block text-sm font-bold text-slate-700"
            >Select Branch</label
          >
          <select
            id="client-branch"
            bind:value={selectedBranchId}
            on:change={handleBranchChange}
            disabled={!selectedCompanyId || loadingBranches}
            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200 disabled:bg-slate-100"
          >
            <option value="">
              {loadingBranches
                ? "Loading branches..."
                : !selectedCompanyId
                  ? "Select a company first"
                  : branches.length === 0
                    ? "No active branches found"
                    : "Select a branch"}
            </option>
            {#each branches as branch (branch.id)}
              <option value={String(branch.id)}
                >{branch.name_en || branch.name_ar}{branch.location_en ||
                branch.location_ar
                  ? ` — ${branch.location_en || branch.location_ar}`
                  : ""}</option
              >
            {/each}
          </select>
          {#if branchError}
            <p class="mt-2 text-sm text-red-600">{branchError}</p>
          {/if}
        </div>

        <div>
          <label
            for="branch-user-search"
            class="mb-2 block text-sm font-bold text-slate-700"
            >Search and Select User</label
          >
          <div class="relative w-full">
            <input
              id="branch-user-search"
              type="search"
              autocomplete="off"
              bind:value={userSearch}
              disabled={!selectedBranchId || loadingUsers}
              placeholder={loadingUsers
                ? "Loading users..."
                : !selectedBranchId
                  ? "Select a branch first"
                  : "Search by English or Arabic name"}
              on:focus={() => (userListOpen = true)}
              on:input={() => {
                selectedUserId = "";
                userListOpen = true;
              }}
              on:blur={closeUserList}
              class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200 disabled:bg-slate-100"
            />
            {#if userListOpen && selectedBranchId && !loadingUsers}
              <div
                class="absolute z-20 mt-1 max-h-60 w-full overflow-y-auto rounded-xl border border-slate-200 bg-white py-1 shadow-xl"
              >
                {#if filteredUsers.length === 0}
                  <p class="px-4 py-3 text-sm text-slate-500">
                    No users found in this branch
                  </p>
                {:else}
                  {#each filteredUsers as user (user.id)}
                    <button
                      type="button"
                      class="flex w-full flex-col items-start px-4 py-3 text-left text-sm hover:bg-emerald-50 {selectedUserId ===
                      user.id
                        ? 'bg-emerald-50 text-emerald-700'
                        : 'text-slate-700'}"
                      on:mousedown|preventDefault={() => selectUser(user)}
                    >
                      <span class="font-semibold text-slate-800">
                        {user.name_en || user.username}
                      </span>
                      <span class="mt-0.5 text-xs text-slate-500">
                        {user.name_ar || user.name_en || user.username}
                      </span>
                    </button>
                  {/each}
                {/if}
              </div>
            {/if}
          </div>
          {#if userError}
            <p class="mt-2 text-sm text-red-600">{userError}</p>
          {/if}
        </div>
      </div>

      {#if loadingEmployeeDetails}
        <div
          class="mt-4 w-full rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs text-slate-500"
        >
          Loading employee details...
        </div>
      {:else if employeeDetailsError}
        <div
          class="mt-4 w-full rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700"
        >
          {employeeDetailsError}
        </div>
      {:else if employeeDetails}
        <div
          class="mt-3 w-full rounded-xl border border-slate-200 bg-white p-3 text-xs shadow-md shadow-slate-200/60"
        >
          <div class="flex items-center gap-3">
            <div
              class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-emerald-50 text-emerald-600"
            >
              <UserRound size={27} strokeWidth={1.8} />
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-lg font-bold text-slate-900">
                {employeeDetails.name_en || "-"}
              </p>
              <p class="truncate text-left text-sm text-slate-500">
                {employeeDetails.name_ar || "-"}
              </p>
            </div>
            <div class="shrink-0 text-center">
              <span
                class="inline-flex rounded-full bg-emerald-50 px-3 py-1 text-sm font-bold text-emerald-700"
              >
                {employeeDetails.id}
              </span>
              <p class="mt-1 text-xs font-medium text-slate-500">Employee ID</p>
            </div>
          </div>

          <div class="my-2 border-t border-slate-200"></div>

          <div class="flex items-center gap-2">
            <div
              class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-500"
            >
              <Building2 size={18} strokeWidth={1.8} />
            </div>
            <div class="min-w-0">
              <p class="text-xs font-medium text-slate-500">
                Selected Branch (Biometric)
              </p>
              <p class="truncate font-bold text-slate-900">
                {selectedBiometricLink?.branchName ||
                  "No biometric branch linked"}
              </p>
            </div>
          </div>

          <div class="mt-2 grid grid-cols-2 divide-x divide-slate-200">
            <div class="flex items-center gap-2 pr-2">
              <div
                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-500"
              >
                <Fingerprint size={18} strokeWidth={1.8} />
              </div>
              <div class="min-w-0">
                <p class="text-xs font-medium text-slate-500">Biometric ID</p>
                <p class="truncate font-bold text-slate-900">
                  {selectedBiometricLink?.biometricId || "Not linked"}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-2 pl-2">
              <div
                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-500"
              >
                <UserRound size={18} strokeWidth={1.8} />
              </div>
              <div class="min-w-0">
                <p class="text-xs font-medium text-slate-500">ERP User</p>
                <p class="truncate font-bold text-slate-900">
                  {#if employeeDetails.erpUser}
                    {employeeDetails.erpUser.username ||
                      employeeDetails.erpUser
                        .userId}{#if employeeDetails.erpUser.username && employeeDetails.erpUser.userId}
                      ({employeeDetails.erpUser.userId})
                    {/if}
                  {:else}
                    Not linked
                  {/if}
                </p>
              </div>
            </div>
          </div>

          <div
            class="mt-2 grid grid-cols-2 divide-x divide-slate-200 border-t border-slate-200 pt-2"
          >
            <div class="flex min-w-0 items-center gap-2 pr-2">
              <div
                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-500"
              >
                <Phone size={18} strokeWidth={1.8} />
              </div>
              <div class="min-w-0">
                <p class="text-xs font-medium text-slate-500">
                  WhatsApp Number
                </p>
                <p class="truncate font-bold text-slate-900">
                  {employeeDetails.whatsapp_number || "Not available"}
                </p>
              </div>
            </div>
            <div class="flex min-w-0 items-center gap-2 pl-2">
              <div
                class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-500"
              >
                <Mail size={18} strokeWidth={1.8} />
              </div>
              <div class="min-w-0">
                <p class="text-xs font-medium text-slate-500">Email</p>
                <p
                  class="truncate font-bold text-slate-900"
                  title={employeeDetails.email}
                >
                  {employeeDetails.email || "Not available"}
                </p>
              </div>
            </div>
          </div>
        </div>
      {/if}
    </div>

    <div class="min-h-0 w-full bg-white p-6 lg:w-[70%]">
      {#if activeTab === "onboarding"}
        <div class="h-full" aria-label="Onboarding content">
          {#if selectedUserId}
            <div class="rounded-2xl border border-slate-200 bg-slate-50 p-6">
              {#if onboardingStep === 1}
                <div class="flex items-start gap-4">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                  >
                    1
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">
                      Sponsorship Status
                    </h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Mark whether the selected employee is under sponsorship.
                    </p>

                    <div class="mt-5 grid max-w-lg grid-cols-2 gap-3">
                      <button
                        type="button"
                        disabled={!selectedUserId}
                        aria-pressed={onboardingSponsorship === true}
                        class="rounded-xl border px-5 py-4 text-left transition disabled:cursor-not-allowed disabled:opacity-50 {onboardingSponsorship ===
                        true
                          ? 'border-emerald-500 bg-emerald-50 text-emerald-800 ring-2 ring-emerald-100'
                          : 'border-slate-200 bg-white text-slate-700 hover:border-emerald-300'}"
                        on:click={() => {
                          onboardingSponsorship = true;
                          sponsorshipError = "";
                          sponsorshipSuccess = "";
                        }}
                      >
                        <span class="block font-bold">Sponsored</span>
                        <span class="mt-1 block text-xs opacity-70"
                          >Yes, under sponsorship</span
                        >
                      </button>
                      <button
                        type="button"
                        disabled={!selectedUserId}
                        aria-pressed={onboardingSponsorship === false}
                        class="rounded-xl border px-5 py-4 text-left transition disabled:cursor-not-allowed disabled:opacity-50 {onboardingSponsorship ===
                        false
                          ? 'border-slate-500 bg-slate-100 text-slate-900 ring-2 ring-slate-100'
                          : 'border-slate-200 bg-white text-slate-700 hover:border-slate-400'}"
                        on:click={() => {
                          onboardingSponsorship = false;
                          selectedSponsorId = "";
                          sponsorshipError = "";
                          sponsorshipSuccess = "";
                        }}
                      >
                        <span class="block font-bold">Not Sponsored</span>
                        <span class="mt-1 block text-xs opacity-70"
                          >No sponsorship</span
                        >
                      </button>
                    </div>

                    {#if !selectedUserId}
                      <p class="mt-3 text-xs font-medium text-amber-600">
                        Select an employee to begin onboarding.
                      </p>
                    {:else}
                      {#if onboardingSponsorship === true}
                        <div class="mt-5 max-w-lg">
                          <label
                            for="sponsor-company"
                            class="mb-2 block text-sm font-bold text-slate-700"
                          >
                            Select Sponsor Company
                          </label>
                          <select
                            id="sponsor-company"
                            bind:value={selectedSponsorId}
                            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                            on:change={() => {
                              sponsorshipError = "";
                              sponsorshipSuccess = "";
                            }}
                          >
                            <option value="">Select a sponsor company</option>
                            {#each companies as company (company.id)}
                              <option value={String(company.id)}>
                                {company.name_en || company.name_ar}
                              </option>
                            {/each}
                          </select>
                          <p class="mt-2 text-xs text-slate-500">
                            The sponsor company is independent from the company
                            connected to the employee's branch.
                          </p>
                        </div>
                      {/if}

                      <div class="mt-5 flex items-center gap-3">
                        <button
                          type="button"
                          disabled={savingSponsorship ||
                            onboardingSponsorship === null ||
                            (onboardingSponsorship === true &&
                              !selectedSponsorId)}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                          on:click={saveSponsorship}
                        >
                          {savingSponsorship ? "Saving..." : "Save Sponsorship"}
                        </button>
                        <button
                          type="button"
                          disabled={savingSponsorship ||
                            onboardingSponsorship === null ||
                            (onboardingSponsorship === true &&
                              !selectedSponsorId)}
                          class="rounded-xl bg-slate-800 px-5 py-3 text-sm font-bold text-white transition hover:bg-slate-900 disabled:cursor-not-allowed disabled:opacity-50"
                          on:click={goToOnboardingStep2}
                        >
                          Next
                        </button>
                        {#if sponsorshipSuccess}
                          <p class="text-sm font-medium text-emerald-600">
                            {sponsorshipSuccess}
                          </p>
                        {/if}
                      </div>
                      {#if sponsorshipError}
                        <p class="mt-3 text-sm font-medium text-red-600">
                          {sponsorshipError}
                        </p>
                      {/if}
                    {/if}
                  </div>
                </div>
              {:else if onboardingStep === 2}
                <div class="flex items-start gap-4">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                  >
                    2
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">
                      Identity Details
                    </h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Review the employee's nationality and identification
                      details.
                    </p>

                    <div
                      class="mt-5 grid max-w-3xl grid-cols-1 gap-4 md:grid-cols-3"
                    >
                      <div>
                        <label
                          for="onboarding-nationality"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Nationality
                        </label>
                        <div class="relative">
                          <input
                            id="onboarding-nationality"
                            type="search"
                            autocomplete="off"
                            bind:value={nationalitySearch}
                            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                            placeholder="Search nationality"
                            on:focus={() => (nationalityListOpen = true)}
                            on:input={() => {
                              onboardingNationalityId = "";
                              nationalityListOpen = true;
                              identityError = "";
                              identitySuccess = "";
                            }}
                            on:blur={closeNationalityList}
                          />
                          {#if nationalityListOpen}
                            <div
                              class="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-slate-200 bg-white py-1 shadow-xl"
                            >
                              {#if filteredNationalities.length === 0}
                                <p class="px-4 py-3 text-sm text-slate-500">
                                  No nationalities found
                                </p>
                              {:else}
                                {#each filteredNationalities as nationality (nationality.id)}
                                  <button
                                    type="button"
                                    class="flex w-full flex-col items-start px-4 py-2 text-left hover:bg-emerald-50"
                                    on:mousedown|preventDefault={() =>
                                      selectNationality(nationality)}
                                  >
                                    <span
                                      class="text-sm font-semibold text-slate-800"
                                    >
                                      {nationality.name_en ||
                                        nationality.name_ar}
                                    </span>
                                    {#if nationality.name_ar}
                                      <span class="text-xs text-slate-500">
                                        {nationality.name_ar}
                                      </span>
                                    {/if}
                                  </button>
                                {/each}
                              {/if}
                            </div>
                          {/if}
                        </div>
                      </div>
                      <div>
                        <label
                          for="onboarding-id-number"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          ID Number
                        </label>
                        <input
                          id="onboarding-id-number"
                          type="text"
                          bind:value={onboardingIdNumber}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                          placeholder="Enter ID number"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-id-expiry"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          ID Expiry Date
                        </label>
                        <input
                          id="onboarding-id-expiry"
                          type="date"
                          bind:value={onboardingIdExpiryDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-date-of-birth"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Date of Birth
                        </label>
                        <input
                          id="onboarding-date-of-birth"
                          type="date"
                          bind:value={onboardingDateOfBirth}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                      {#if isNonSaudiEmployee}
                        <div>
                          <label
                            for="onboarding-work-permit-expiry"
                            class="mb-2 block text-sm font-bold text-slate-700"
                          >
                            Work Permit Expiry Date
                          </label>
                          <input
                            id="onboarding-work-permit-expiry"
                            type="date"
                            bind:value={onboardingWorkPermitExpiryDate}
                            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                          />
                        </div>
                      {/if}
                    </div>

                    <div
                      class="mt-4 max-w-3xl rounded-xl border border-slate-200 bg-white p-4"
                    >
                      <div
                        class="flex flex-wrap items-center justify-between gap-3"
                      >
                        <div>
                          <p class="text-sm font-bold text-slate-800">
                            ID Document
                          </p>
                          <p class="mt-1 text-xs text-slate-500">
                            PDF, JPG, or PNG · maximum 10 MB
                          </p>
                        </div>
                        <div class="flex items-center gap-2">
                          {#if idDocumentUrl}
                            <a
                              href={idDocumentUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-bold text-slate-700 hover:bg-slate-100"
                            >
                              <ExternalLink size={16} />
                              View Document
                            </a>
                          {/if}
                          <button
                            type="button"
                            disabled={uploadingIdDocument}
                            class="inline-flex items-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                            on:click={chooseIdDocument}
                          >
                            <FileUp size={16} />
                            {uploadingIdDocument
                              ? "Uploading..."
                              : idDocumentUrl
                                ? "Update Document"
                                : "Upload Document"}
                          </button>
                          <input
                            bind:this={idDocumentInput}
                            type="file"
                            accept="application/pdf,image/jpeg,image/png"
                            class="hidden"
                            on:change={uploadIdDocument}
                          />
                        </div>
                      </div>
                      {#if idDocumentSuccess}
                        <p class="mt-3 text-sm font-medium text-emerald-600">
                          {idDocumentSuccess}
                        </p>
                      {/if}
                      {#if idDocumentError}
                        <p class="mt-3 text-sm font-medium text-red-600">
                          {idDocumentError}
                        </p>
                      {/if}
                    </div>

                    {#if nationalityError}
                      <p class="mt-3 text-sm font-medium text-red-600">
                        {nationalityError}
                      </p>
                    {/if}

                    <div class="mt-5 flex items-center gap-3">
                      <button
                        type="button"
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100"
                        on:click={() => (onboardingStep = 1)}
                      >
                        Back
                      </button>
                      {#if identityChanged}
                        <button
                          type="button"
                          disabled={savingIdentity}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                          on:click={saveIdentityDetails}
                        >
                          {savingIdentity ? "Saving..." : "Save Changes"}
                        </button>
                      {/if}
                      <button
                        type="button"
                        disabled={savingIdentity}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                        on:click={goToOnboardingStep3}
                      >
                        {savingIdentity ? "Saving..." : "Next"}
                      </button>
                      {#if identitySuccess}
                        <p class="text-sm font-medium text-emerald-600">
                          {identitySuccess}
                        </p>
                      {/if}
                    </div>
                    {#if identityError}
                      <p class="mt-3 text-sm font-medium text-red-600">
                        {identityError}
                      </p>
                    {/if}
                  </div>
                </div>
              {:else if onboardingStep === 3}
                <div class="flex items-start gap-4">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                  >
                    3
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">
                      Health Card
                    </h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Review and complete the employee's health card details.
                    </p>

                    <div
                      class="mt-5 grid max-w-3xl grid-cols-1 gap-4 md:grid-cols-3"
                    >
                      <div>
                        <label
                          for="onboarding-health-card-number"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Health Card Number
                        </label>
                        <input
                          id="onboarding-health-card-number"
                          type="text"
                          bind:value={healthCardNumber}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                          placeholder="Enter health card number"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-health-card-expiry"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Health Card Expiry Date
                        </label>
                        <input
                          id="onboarding-health-card-expiry"
                          type="date"
                          bind:value={healthCardExpiryDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-health-education-expiry"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Health Education Expiry Date
                        </label>
                        <input
                          id="onboarding-health-education-expiry"
                          type="date"
                          bind:value={healthEducationExpiryDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                    </div>

                    <div
                      class="mt-4 max-w-2xl rounded-xl border border-slate-200 bg-white p-4"
                    >
                      <div
                        class="flex flex-wrap items-center justify-between gap-3"
                      >
                        <div>
                          <p class="text-sm font-bold text-slate-800">
                            Health Card Document
                          </p>
                          <p class="mt-1 text-xs text-slate-500">
                            PDF, JPG, or PNG · maximum 10 MB
                          </p>
                        </div>
                        <div class="flex items-center gap-2">
                          {#if healthCardDocumentUrl}
                            <a
                              href={healthCardDocumentUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-bold text-slate-700 hover:bg-slate-100"
                            >
                              <ExternalLink size={16} />
                              View Document
                            </a>
                          {/if}
                          <button
                            type="button"
                            disabled={uploadingHealthCardDocument}
                            class="inline-flex items-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                            on:click={chooseHealthCardDocument}
                          >
                            <FileUp size={16} />
                            {uploadingHealthCardDocument
                              ? "Uploading..."
                              : healthCardDocumentUrl
                                ? "Update Document"
                                : "Upload Document"}
                          </button>
                          <input
                            bind:this={healthCardDocumentInput}
                            type="file"
                            accept="application/pdf,image/jpeg,image/png"
                            class="hidden"
                            on:change={uploadHealthCardDocument}
                          />
                        </div>
                      </div>
                    </div>

                    <div class="mt-5 flex items-center gap-3">
                      <button
                        type="button"
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100"
                        on:click={() => (onboardingStep = 2)}
                      >
                        Back
                      </button>
                      {#if healthCardChanged}
                        <button
                          type="button"
                          disabled={savingHealthCard}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                          on:click={saveHealthCardDetails}
                        >
                          {savingHealthCard ? "Saving..." : "Save Changes"}
                        </button>
                      {/if}
                      <button
                        type="button"
                        disabled={savingHealthCard}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                        on:click={goToOnboardingStep4}
                      >
                        {savingHealthCard ? "Saving..." : "Next"}
                      </button>
                      {#if healthCardSuccess}
                        <p class="text-sm font-medium text-emerald-600">
                          {healthCardSuccess}
                        </p>
                      {/if}
                    </div>
                    {#if healthCardError}
                      <p class="mt-3 text-sm font-medium text-red-600">
                        {healthCardError}
                      </p>
                    {/if}
                  </div>
                </div>
              {:else if onboardingStep === 4}
                <div class="flex items-start gap-4">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                  >
                    4
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">
                      Driving Licence
                    </h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Review and complete the employee's driving licence
                      details.
                    </p>

                    <div
                      class="mt-5 grid max-w-2xl grid-cols-1 gap-4 md:grid-cols-2"
                    >
                      <div>
                        <label
                          for="onboarding-driving-licence-number"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Driving Licence Number
                        </label>
                        <input
                          id="onboarding-driving-licence-number"
                          type="text"
                          bind:value={drivingLicenceNumber}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                          placeholder="Enter driving licence number"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-driving-licence-expiry"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Driving Licence Expiry Date
                        </label>
                        <input
                          id="onboarding-driving-licence-expiry"
                          type="date"
                          bind:value={drivingLicenceExpiryDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                    </div>

                    <div
                      class="mt-4 max-w-2xl rounded-xl border border-slate-200 bg-white p-4"
                    >
                      <div
                        class="flex flex-wrap items-center justify-between gap-3"
                      >
                        <div>
                          <p class="text-sm font-bold text-slate-800">
                            Driving Licence Document
                          </p>
                          <p class="mt-1 text-xs text-slate-500">
                            PDF, JPG, or PNG · maximum 10 MB
                          </p>
                        </div>
                        <div class="flex items-center gap-2">
                          {#if drivingLicenceDocumentUrl}
                            <a
                              href={drivingLicenceDocumentUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-bold text-slate-700 hover:bg-slate-100"
                            >
                              <ExternalLink size={16} />
                              View Document
                            </a>
                          {/if}
                          <button
                            type="button"
                            disabled={uploadingDrivingLicenceDocument}
                            class="inline-flex items-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                            on:click={chooseDrivingLicenceDocument}
                          >
                            <FileUp size={16} />
                            {uploadingDrivingLicenceDocument
                              ? "Uploading..."
                              : drivingLicenceDocumentUrl
                                ? "Update Document"
                                : "Upload Document"}
                          </button>
                          <input
                            bind:this={drivingLicenceDocumentInput}
                            type="file"
                            accept="application/pdf,image/jpeg,image/png"
                            class="hidden"
                            on:change={uploadDrivingLicenceDocument}
                          />
                        </div>
                      </div>
                    </div>

                    <div class="mt-5 flex items-center gap-3">
                      <button
                        type="button"
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100"
                        on:click={() => (onboardingStep = 3)}
                      >
                        Back
                      </button>
                      {#if drivingLicenceChanged}
                        <button
                          type="button"
                          disabled={savingDrivingLicence}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                          on:click={saveDrivingLicenceDetails}
                        >
                          {savingDrivingLicence ? "Saving..." : "Save Changes"}
                        </button>
                      {/if}
                      <button
                        type="button"
                        disabled={savingDrivingLicence}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                        on:click={goToOnboardingStep5}
                      >
                        {savingDrivingLicence ? "Saving..." : "Next"}
                      </button>
                      {#if drivingLicenceSuccess}
                        <p class="text-sm font-medium text-emerald-600">
                          {drivingLicenceSuccess}
                        </p>
                      {/if}
                    </div>
                    {#if drivingLicenceError}
                      <p class="mt-3 text-sm font-medium text-red-600">
                        {drivingLicenceError}
                      </p>
                    {/if}
                  </div>
                </div>
              {:else if onboardingStep === 5}
                <div class="flex items-start gap-4">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                  >
                    5
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">Contract</h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Review and complete the employee's contract details.
                    </p>

                    <div
                      class="mt-5 grid max-w-3xl grid-cols-1 gap-4 md:grid-cols-3"
                    >
                      <div>
                        <label
                          for="onboarding-contract-expiry"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Contract Expiry Date
                        </label>
                        <input
                          id="onboarding-contract-expiry"
                          type="date"
                          bind:value={contractExpiryDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-probation-expiry"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Probation Period Expiry Date
                        </label>
                        <input
                          id="onboarding-probation-expiry"
                          type="date"
                          bind:value={probationPeriodExpiryDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-joining-date"
                          class="mb-2 block text-sm font-bold text-slate-700"
                        >
                          Joining Date
                        </label>
                        <input
                          id="onboarding-joining-date"
                          type="date"
                          bind:value={joiningDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                    </div>

                    <div
                      class="mt-4 max-w-2xl rounded-xl border border-slate-200 bg-white p-4"
                    >
                      <div
                        class="flex flex-wrap items-center justify-between gap-3"
                      >
                        <div>
                          <p class="text-sm font-bold text-slate-800">
                            Contract Document
                          </p>
                          <p class="mt-1 text-xs text-slate-500">
                            PDF, JPG, or PNG · maximum 10 MB
                          </p>
                        </div>
                        <div class="flex items-center gap-2">
                          {#if contractDocumentUrl}
                            <a
                              href={contractDocumentUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-bold text-slate-700 hover:bg-slate-100"
                            >
                              <ExternalLink size={16} />
                              View Document
                            </a>
                          {/if}
                          <button
                            type="button"
                            disabled={uploadingContractDocument}
                            class="inline-flex items-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                            on:click={chooseContractDocument}
                          >
                            <FileUp size={16} />
                            {uploadingContractDocument
                              ? "Uploading..."
                              : contractDocumentUrl
                                ? "Update Document"
                                : "Upload Document"}
                          </button>
                          <input
                            bind:this={contractDocumentInput}
                            type="file"
                            accept="application/pdf,image/jpeg,image/png"
                            class="hidden"
                            on:change={uploadContractDocument}
                          />
                        </div>
                      </div>
                    </div>

                    <div class="mt-5 flex items-center gap-3">
                      <button
                        type="button"
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100"
                        on:click={() => (onboardingStep = 4)}
                      >
                        Back
                      </button>
                      {#if contractChanged}
                        <button
                          type="button"
                          disabled={savingContract}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                          on:click={saveContractDetails}
                        >
                          {savingContract ? "Saving..." : "Save Changes"}
                        </button>
                      {/if}
                      <button
                        type="button"
                        disabled={savingContract}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                        on:click={goToOnboardingStep6}
                      >
                        {savingContract ? "Saving..." : "Next"}
                      </button>
                      {#if contractSuccess}
                        <p class="text-sm font-medium text-emerald-600">
                          {contractSuccess}
                        </p>
                      {/if}
                    </div>
                    {#if contractError}
                      <p class="mt-3 text-sm font-medium text-red-600">
                        {contractError}
                      </p>
                    {/if}
                  </div>
                </div>
              {:else if onboardingStep === 6}
                <div class="flex items-start gap-4">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                  >
                    6
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">
                      Health Insurance
                    </h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Select the employee's health-insurance company and expiry
                      date.
                    </p>

                    <div
                      class="mt-5 grid max-w-2xl grid-cols-1 gap-4 md:grid-cols-2"
                    >
                      <div>
                        <div
                          class="mb-2 flex items-center justify-between gap-2"
                        >
                          <label
                            for="onboarding-insurance-company"
                            class="text-sm font-bold text-slate-700"
                            >Insurance Company</label
                          >
                          <button
                            type="button"
                            class="text-sm font-bold text-emerald-700 hover:text-emerald-800"
                            on:click={() => (showCreateInsuranceCompany = true)}
                            >+ Create Company</button
                          >
                        </div>
                        <div class="relative">
                          <input
                            id="onboarding-insurance-company"
                            type="search"
                            autocomplete="off"
                            bind:value={insuranceCompanySearch}
                            placeholder="Search insurance company"
                            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                            on:focus={() => (insuranceCompanyListOpen = true)}
                            on:input={() => {
                              selectedInsuranceCompanyId = "";
                              insuranceCompanyListOpen = true;
                              insuranceError = "";
                              insuranceSuccess = "";
                            }}
                            on:blur={closeInsuranceCompanyList}
                          />
                          {#if insuranceCompanyListOpen}
                            <div
                              class="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-slate-200 bg-white py-1 shadow-xl"
                            >
                              {#if filteredInsuranceCompanies.length === 0}
                                <p class="px-4 py-3 text-sm text-slate-500">
                                  No insurance companies found
                                </p>
                              {:else}
                                {#each filteredInsuranceCompanies as company (company.id)}
                                  <button
                                    type="button"
                                    class="flex w-full flex-col items-start px-4 py-2 text-left hover:bg-emerald-50"
                                    on:mousedown|preventDefault={() =>
                                      selectInsuranceCompany(company)}
                                  >
                                    <span
                                      class="text-sm font-semibold text-slate-800"
                                      >{company.name_en ||
                                        company.name_ar}</span
                                    >
                                    {#if company.name_ar}<span
                                        class="text-xs text-slate-500"
                                        >{company.name_ar}</span
                                      >{/if}
                                  </button>
                                {/each}
                              {/if}
                            </div>
                          {/if}
                        </div>
                      </div>
                      <div>
                        <label
                          for="onboarding-insurance-expiry"
                          class="mb-2 block text-sm font-bold text-slate-700"
                          >Insurance Expiry Date</label
                        >
                        <input
                          id="onboarding-insurance-expiry"
                          type="date"
                          bind:value={insuranceExpiryDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                    </div>

                    <div class="mt-5 flex items-center gap-3">
                      <button
                        type="button"
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100"
                        on:click={() => (onboardingStep = 5)}>Back</button
                      >
                      {#if insuranceChanged}
                        <button
                          type="button"
                          disabled={savingInsurance}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                          on:click={saveInsuranceDetails}
                          >{savingInsurance
                            ? "Saving..."
                            : "Save Changes"}</button
                        >
                      {/if}
                      <button
                        type="button"
                        disabled={savingInsurance}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                        on:click={goToOnboardingStep7}
                      >
                        {savingInsurance ? "Saving..." : "Next"}
                      </button>
                      {#if insuranceSuccess}<p
                          class="text-sm font-medium text-emerald-600"
                        >
                          {insuranceSuccess}
                        </p>{/if}
                    </div>
                    {#if insuranceError}<p
                        class="mt-3 text-sm font-medium text-red-600"
                      >
                        {insuranceError}
                      </p>{/if}
                  </div>
                </div>
              {:else if onboardingStep === 7}
                <div class="flex items-start gap-4">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                  >
                    7
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">
                      Bank Details
                    </h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Review and complete the employee's bank information.
                    </p>
                    <div
                      class="mt-5 grid max-w-2xl grid-cols-1 gap-4 md:grid-cols-2"
                    >
                      <div>
                        <label
                          for="onboarding-bank-name"
                          class="mb-2 block text-sm font-bold text-slate-700"
                          >Bank Name</label
                        >
                        <input
                          id="onboarding-bank-name"
                          type="text"
                          bind:value={bankName}
                          placeholder="Enter bank name"
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-iban"
                          class="mb-2 block text-sm font-bold text-slate-700"
                          >IBAN</label
                        >
                        <input
                          id="onboarding-iban"
                          type="text"
                          bind:value={iban}
                          placeholder="Enter IBAN"
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm uppercase text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                    </div>
                    <div class="mt-5 flex items-center gap-3">
                      <button
                        type="button"
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100"
                        on:click={() => (onboardingStep = 6)}>Back</button
                      >
                      {#if bankDetailsChanged}
                        <button
                          type="button"
                          disabled={savingBankDetails}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                          on:click={saveBankDetails}
                          >{savingBankDetails
                            ? "Saving..."
                            : "Save Changes"}</button
                        >
                      {/if}
                      <button
                        type="button"
                        disabled={savingBankDetails}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                        on:click={goToOnboardingStep8}
                      >
                        {savingBankDetails ? "Saving..." : "Next"}
                      </button>
                      {#if bankDetailsSuccess}<p
                          class="text-sm font-medium text-emerald-600"
                        >
                          {bankDetailsSuccess}
                        </p>{/if}
                    </div>
                    {#if bankDetailsError}<p
                        class="mt-3 text-sm font-medium text-red-600"
                      >
                        {bankDetailsError}
                      </p>{/if}
                  </div>
                </div>
              {:else}
                <div class="flex items-start gap-4">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                  >
                    8
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">
                      Employee Status
                    </h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Set the employee's starting work status. The effective
                      date uses the Joining Date.
                    </p>

                    <div
                      class="mt-5 grid max-w-2xl grid-cols-1 gap-3 md:grid-cols-2"
                    >
                      <button
                        type="button"
                        class="rounded-xl border p-4 text-left transition {onboardingEmploymentStatus ===
                        'Job (With Finger)'
                          ? 'border-emerald-500 bg-emerald-50 ring-2 ring-emerald-100'
                          : 'border-slate-200 bg-white hover:border-emerald-300'}"
                        on:click={() => {
                          onboardingEmploymentStatus = "Job (With Finger)";
                          employmentStatusError = "";
                          employmentStatusSuccess = "";
                        }}
                      >
                        <span class="block text-sm font-bold text-slate-800"
                          >Job (With Finger)</span
                        >
                        <span class="mt-1 block text-xs text-slate-500"
                          >Attendance by fingerprint</span
                        >
                      </button>
                      <button
                        type="button"
                        class="rounded-xl border p-4 text-left transition {onboardingEmploymentStatus ===
                        'Remote Job'
                          ? 'border-emerald-500 bg-emerald-50 ring-2 ring-emerald-100'
                          : 'border-slate-200 bg-white hover:border-emerald-300'}"
                        on:click={() => {
                          onboardingEmploymentStatus = "Remote Job";
                          employmentStatusError = "";
                          employmentStatusSuccess = "";
                        }}
                      >
                        <span class="block text-sm font-bold text-slate-800"
                          >Remote Job</span
                        >
                        <span class="mt-1 block text-xs text-slate-500"
                          >Remote attendance</span
                        >
                      </button>
                    </div>

                    <div
                      class="mt-4 grid max-w-2xl grid-cols-1 gap-4 md:grid-cols-2"
                    >
                      <div>
                        <label
                          for="onboarding-status-date"
                          class="mb-2 block text-sm font-bold text-slate-700"
                          >Effective Date</label
                        >
                        <input
                          id="onboarding-status-date"
                          type="date"
                          bind:value={employmentStatusEffectiveDate}
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                      <div>
                        <label
                          for="onboarding-status-reason"
                          class="mb-2 block text-sm font-bold text-slate-700"
                          >Reason</label
                        >
                        <input
                          id="onboarding-status-reason"
                          type="text"
                          bind:value={employmentStatusReason}
                          placeholder="Enter status reason"
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                      </div>
                    </div>

                    {#if savedEmploymentStatus}
                      <p class="mt-3 text-xs text-slate-500">
                        Current status: <strong>{savedEmploymentStatus}</strong>
                      </p>
                    {/if}
                    <div class="mt-5 flex items-center gap-3">
                      <button
                        type="button"
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100"
                        on:click={() => (onboardingStep = 7)}>Back</button
                      >
                      <button
                        type="button"
                        disabled={savingEmploymentStatus ||
                          !onboardingEmploymentStatus ||
                          !employmentStatusEffectiveDate}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
                        on:click={saveEmploymentStatus}
                        >{savingEmploymentStatus
                          ? "Saving..."
                          : "Complete Onboarding"}</button
                      >
                      {#if employmentStatusSuccess}<p
                          class="text-sm font-medium text-emerald-600"
                        >
                          {employmentStatusSuccess}
                        </p>{/if}
                    </div>
                    {#if employmentStatusError}<p
                        class="mt-3 text-sm font-medium text-red-600"
                      >
                        {employmentStatusError}
                      </p>{/if}
                  </div>
                </div>
              {/if}
            </div>
          {/if}
        </div>
      {:else}
        <div class="h-full" aria-label="Transfers content">
          {#if selectedUserId && employeeDetails}
            <div class="rounded-2xl border border-slate-200 bg-slate-50 p-6">
              {#if transferStep === 1}
              <div class="flex items-start gap-4">
                <div
                  class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white"
                >
                  1
                </div>
                <div class="min-w-0 flex-1">
                  <h2 class="text-lg font-bold text-slate-900">
                    Transfer Destination
                  </h2>
                  <p class="mt-1 text-sm text-slate-500">
                    Select the company and active branch to which the employee
                    will transfer.
                  </p>

                  <div
                    class="mt-5 grid max-w-2xl grid-cols-1 gap-4 md:grid-cols-2"
                  >
                    <div>
                      <label
                        for="transfer-company"
                        class="mb-2 block text-sm font-bold text-slate-700"
                        >Transfer To Company</label
                      >
                      <select
                        id="transfer-company"
                        bind:value={transferCompanyId}
                        on:change={handleTransferCompanyChange}
                        class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                      >
                        <option value="">Select a company</option>
                        {#each companies as company (company.id)}
                          <option value={String(company.id)}
                            >{company.name_en || company.name_ar}</option
                          >
                        {/each}
                      </select>
                    </div>
                    <div>
                      <label
                        for="transfer-branch"
                        class="mb-2 block text-sm font-bold text-slate-700"
                        >Transfer To Branch</label
                      >
                      <select
                        id="transfer-branch"
                        bind:value={transferBranchId}
                        on:change={handleTransferBranchChange}
                        disabled={!transferCompanyId || loadingTransferBranches}
                        class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200 disabled:cursor-not-allowed disabled:bg-slate-100"
                      >
                        <option value=""
                          >{loadingTransferBranches
                            ? "Loading branches..."
                            : transferCompanyId
                              ? "Select a branch"
                              : "Select a company first"}</option
                        >
                        {#each transferBranches as branch (branch.id)}
                          <option value={String(branch.id)}
                            >{branch.name_en ||
                              branch.name_ar}{branch.location_en ||
                            branch.location_ar
                              ? ` — ${branch.location_en || branch.location_ar}`
                              : ""}</option
                          >
                        {/each}
                      </select>
                      {#if transferBranchError}<p
                          class="mt-2 text-sm text-red-600"
                        >
                          {transferBranchError}
                        </p>{/if}
                    </div>
                  </div>
                  {#if transferBranchId}
                    <div class="mt-5 max-w-2xl">
                      <label class="mb-2 block text-sm font-bold text-slate-700"
                        >Destination Biometric ID</label
                      >
                      {#if loadingTransferBiometrics}
                        <div class="rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-500">
                          Loading biometric IDs...
                        </div>
                      {:else if transferBiometricId && !transferBiometricSearch}
                        <div class="flex items-center gap-3 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3">
                          <Fingerprint class="h-5 w-5 text-emerald-600" />
                          <div>
                            <p class="text-xs font-medium text-slate-500">Linked Biometric ID</p>
                            <p class="font-bold text-slate-900">{transferBiometricId}</p>
                          </div>
                        </div>
                      {:else}
                        <div class="relative">
                          <input
                            type="text"
                            bind:value={transferBiometricSearch}
                            on:focus={() => (transferBiometricListOpen = true)}
                            placeholder="Search by biometric ID or employee name"
                            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                          />
                          {#if transferBiometricListOpen}
                            <div class="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-slate-200 bg-white shadow-lg">
                              {#each filteredTransferBiometrics as candidate (candidate.biometric_id)}
                                <button
                                  type="button"
                                  on:click={() => selectTransferBiometric(candidate)}
                                  class="block w-full border-b border-slate-100 px-4 py-3 text-left last:border-0 hover:bg-emerald-50"
                                >
                                  <span class="block text-sm font-bold text-slate-800">{candidate.biometric_id}</span>
                                  <span class="block text-xs text-slate-500">{candidate.name}</span>
                                </button>
                              {:else}
                                <p class="px-4 py-3 text-sm text-slate-500">No available biometric IDs found.</p>
                              {/each}
                            </div>
                          {/if}
                        </div>
                      {/if}
                      {#if transferBiometricError}<p class="mt-2 text-sm text-red-600">{transferBiometricError}</p>{/if}
                    </div>
                  {/if}
                  <div class="mt-5 flex flex-wrap items-center gap-3">
                    <button
                      type="button"
                      on:click={openTransferClaimsStep}
                      disabled={!transferBranchId || !transferBiometricId || loadingTransferClaims}
                      class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white transition-colors hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                    >
                      {loadingTransferClaims ? "Loading..." : "Next"}
                    </button>
                    {#if transferSaveError}<p
                        class="text-sm font-medium text-red-600"
                      >
                        {transferSaveError}
                      </p>{/if}
                    {#if transferClaimsError}<p
                        class="text-sm font-medium text-red-600"
                      >
                        {transferClaimsError}
                      </p>{/if}
                  </div>
                </div>
              </div>
              {:else if transferStep === 2}
                <div class="flex items-start gap-4">
                  <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white">
                    2
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">Product Claims</h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Move the employee's source-branch product claims to In Process. They can be assigned later from Product Claim Manager.
                    </p>

                    <div class="mt-5 max-w-2xl rounded-xl border border-slate-200 bg-white px-5 py-4">
                      <p class="text-sm font-medium text-slate-500">Total Product Claims</p>
                      <p class="mt-1 text-3xl font-bold text-slate-900">{transferClaimCount}</p>
                    </div>

                    {#if transferClaimCount > 0 && !transferClaimsProcessed}
                      <p class="mt-4 text-sm font-medium text-amber-700">
                        Process these claims before continuing to the next step.
                      </p>
                    {:else if transferClaimsSuccess}
                      <p class="mt-4 text-sm font-medium text-emerald-700">
                        {transferClaimsSuccess}
                      </p>
                    {:else}
                      <p class="mt-4 text-sm font-medium text-emerald-700">
                        No product claims need to be moved.
                      </p>
                    {/if}

                    <div class="mt-6 flex flex-wrap items-center gap-3">
                      <button
                        type="button"
                        on:click={() => {
                          transferStep = 1;
                          transferSaveError = "";
                          transferSaveSuccess = "";
                        }}
                        disabled={savingTransfer}
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        Back
                      </button>
                      {#if transferClaimCount > 0 && !transferClaimsProcessed}
                        <button
                          type="button"
                          on:click={processTransferClaims}
                          disabled={processingTransferClaims}
                          class="rounded-xl bg-amber-600 px-5 py-3 text-sm font-bold text-white transition-colors hover:bg-amber-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                        >
                          {processingTransferClaims ? "Processing..." : "Process Claims"}
                        </button>
                      {:else}
                        <button
                          type="button"
                          on:click={openTransferPositionStep}
                          disabled={loadingTransferPositions}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white transition-colors hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                        >
                          {loadingTransferPositions ? "Loading..." : "Next"}
                        </button>
                      {/if}
                      {#if transferClaimsError}<p class="text-sm font-medium text-red-600">{transferClaimsError}</p>{/if}
                      {#if transferPositionError}<p class="text-sm font-medium text-red-600">{transferPositionError}</p>{/if}
                    </div>
                  </div>
                </div>
              {:else if transferStep === 3}
                <div class="flex items-start gap-4">
                  <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white">
                    3
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">Position Change</h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Keep the current employee position or select a new one. Branch Default Positions are handled separately in the next step.
                    </p>

                    <div class="mt-5 max-w-2xl">
                      <button
                        type="button"
                        on:click={() => {
                          keepCurrentPosition = true;
                          transferPositionId = "";
                          savedTransferPositionId = "";
                          transferPositionSuccess = "";
                          transferPositionSearch = "";
                          transferPositionListOpen = false;
                          transferPositionError = "";
                        }}
                        class="mb-4 w-full rounded-xl border px-4 py-3 text-left transition-colors {keepCurrentPosition ? 'border-emerald-500 bg-emerald-50' : 'border-slate-300 bg-white hover:bg-slate-50'}"
                      >
                        <span class="block text-sm font-bold text-slate-800">Keep Current Position (As Is)</span>
                        <span class="mt-1 block text-xs text-slate-500">
                          {currentTransferPosition
                            ? currentTransferPosition.title_en || currentTransferPosition.title_ar
                            : "No position currently assigned"}
                        </span>
                        {#if currentTransferPosition?.title_ar && currentTransferPosition.title_ar !== currentTransferPosition.title_en}
                          <span class="block text-xs text-slate-500" dir="rtl">{currentTransferPosition.title_ar}</span>
                        {/if}
                      </button>
                      <label for="transfer-position" class="mb-2 block text-sm font-bold text-slate-700">
                        Or Select New Position
                      </label>
                      <div class="relative">
                        <input
                          id="transfer-position"
                          type="text"
                          bind:value={transferPositionSearch}
                          on:input={() => {
                            keepCurrentPosition = false;
                            transferPositionId = "";
                            savedTransferPositionId = "";
                            transferPositionSuccess = "";
                            transferPositionListOpen = true;
                          }}
                          on:focus={() => {
                            keepCurrentPosition = false;
                            transferPositionListOpen = true;
                          }}
                          placeholder="Search and select a position"
                          class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                        />
                        {#if transferPositionListOpen}
                          <div class="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-slate-200 bg-white shadow-lg">
                            {#each filteredTransferPositions as position (position.id)}
                              <button
                                type="button"
                                on:click={() => selectTransferPosition(position)}
                                class="block w-full border-b border-slate-100 px-4 py-3 text-left last:border-0 hover:bg-emerald-50"
                              >
                                <span class="block text-sm font-bold text-slate-800">{position.title_en || position.title_ar}</span>
                                {#if position.title_ar && position.title_ar !== position.title_en}
                                  <span class="block text-xs text-slate-500" dir="rtl">{position.title_ar}</span>
                                {/if}
                              </button>
                            {:else}
                              <p class="px-4 py-3 text-sm text-slate-500">No other active positions found.</p>
                            {/each}
                          </div>
                        {/if}
                      </div>
                    </div>

                    <div class="mt-6 flex flex-wrap items-center gap-3">
                      <button
                        type="button"
                        on:click={() => {
                          transferStep = 2;
                          transferSaveError = "";
                          transferSaveSuccess = "";
                        }}
                        disabled={savingTransfer}
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        Back
                      </button>
                      {#if !keepCurrentPosition && transferPositionId && savedTransferPositionId !== transferPositionId}
                        <button
                          type="button"
                          on:click={saveTransferPosition}
                          disabled={savingTransferPosition}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white transition-colors hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                        >
                          {savingTransferPosition ? "Saving..." : "Save Position"}
                        </button>
                      {/if}
                      {#if keepCurrentPosition || (transferPositionId && savedTransferPositionId === transferPositionId)}
                        <button
                          type="button"
                          on:click={openDefaultPositionsStep}
                          disabled={loadingDefaultPositionHandoff || savingTransferPosition}
                          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white transition-colors hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                        >
                          {loadingDefaultPositionHandoff ? "Loading..." : "Next"}
                        </button>
                      {/if}
                      {#if transferPositionSuccess}<p class="text-sm font-medium text-emerald-700">{transferPositionSuccess}</p>{/if}
                      {#if transferPositionError}<p class="text-sm font-medium text-red-600">{transferPositionError}</p>{/if}
                      {#if defaultPositionError}<p class="text-sm font-medium text-red-600">{defaultPositionError}</p>{/if}
                    </div>
                  </div>
                </div>
              {:else if transferStep === 4}
                <div class="flex items-start gap-4">
                  <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white">
                    4
                  </div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">Default Positions</h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Reassign any source-branch default positions held by the transferring employee.
                    </p>

                    <div class="mt-5 max-w-2xl rounded-xl border border-slate-200 bg-white px-5 py-4">
                      <p class="text-sm font-medium text-slate-500">Assigned Default Positions</p>
                      <p class="mt-1 text-3xl font-bold text-slate-900">{defaultPositionAssignmentCount}</p>
                    </div>

                    {#if defaultPositionAssignmentCount > 0}
                      <div class="mt-5 max-w-2xl">
                        <label for="default-position-replacement" class="mb-2 block text-sm font-bold text-slate-700">
                          Replace With
                        </label>
                        <div class="relative">
                          <input
                            id="default-position-replacement"
                            type="text"
                            bind:value={defaultReplacementSearch}
                            on:input={() => {
                              defaultReplacementUserId = "";
                              defaultReplacementListOpen = true;
                            }}
                            on:focus={() => (defaultReplacementListOpen = true)}
                            placeholder="Search a user from the source branch"
                            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                          />
                          {#if defaultReplacementListOpen}
                            <div class="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-slate-200 bg-white shadow-lg">
                              {#each filteredDefaultReplacementUsers as user (user.user_id)}
                                <button
                                  type="button"
                                  on:click={() => selectDefaultReplacementUser(user)}
                                  class="block w-full border-b border-slate-100 px-4 py-3 text-left last:border-0 hover:bg-emerald-50"
                                >
                                  <span class="block text-sm font-bold text-slate-800">{user.name_en || user.name_ar || user.username}</span>
                                  {#if user.name_ar && user.name_ar !== user.name_en}
                                    <span class="block text-xs text-slate-500" dir="rtl">{user.name_ar}</span>
                                  {/if}
                                  <span class="block text-xs text-slate-400">{user.employee_id}</span>
                                </button>
                              {:else}
                                <p class="px-4 py-3 text-sm text-slate-500">No eligible users found in the source branch.</p>
                              {/each}
                            </div>
                          {/if}
                        </div>
                      </div>
                    {:else}
                      <p class="mt-4 text-sm font-medium text-emerald-700">
                        No default positions need to be reassigned.
                      </p>
                    {/if}

                    <div class="mt-6 flex flex-wrap items-center gap-3">
                      <button
                        type="button"
                        on:click={() => {
                          transferStep = 3;
                          transferSaveError = "";
                          transferSaveSuccess = "";
                        }}
                        disabled={savingTransfer}
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        Back
                      </button>
                      <button
                        type="button"
                        on:click={openEntryTaskStep}
                        disabled={loadingEntryTaskHandoff || (defaultPositionAssignmentCount > 0 && !defaultReplacementUserId)}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white transition-colors hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                      >
                        {loadingEntryTaskHandoff ? "Loading..." : "Next"}
                      </button>
                      {#if defaultPositionError}<p class="text-sm font-medium text-red-600">{defaultPositionError}</p>{/if}
                      {#if entryTaskError}<p class="text-sm font-medium text-red-600">{entryTaskError}</p>{/if}
                    </div>
                  </div>
                </div>
              {:else if transferStep === 5}
                <div class="flex items-start gap-4">
                  <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white">5</div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">Entry Task User</h2>
                    <p class="mt-1 text-sm text-slate-500">
                      Replace the source branch's default Entry Task User when assigned to the transferring employee.
                    </p>

                    {#if isEntryTaskUser}
                      <div class="mt-5 max-w-2xl">
                        <label for="entry-task-replacement" class="mb-2 block text-sm font-bold text-slate-700">Replace With</label>
                        <div class="relative">
                          <input
                            id="entry-task-replacement"
                            type="text"
                            bind:value={entryTaskReplacementSearch}
                            on:input={() => {
                              entryTaskReplacementUserId = "";
                              entryTaskReplacementListOpen = true;
                            }}
                            on:focus={() => (entryTaskReplacementListOpen = true)}
                            placeholder="Search a user from the source branch"
                            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm text-slate-800 outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
                          />
                          {#if entryTaskReplacementListOpen}
                            <div class="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-slate-200 bg-white shadow-lg">
                              {#each filteredEntryTaskReplacementUsers as user (user.user_id)}
                                <button
                                  type="button"
                                  on:click={() => selectEntryTaskReplacementUser(user)}
                                  class="block w-full border-b border-slate-100 px-4 py-3 text-left last:border-0 hover:bg-emerald-50"
                                >
                                  <span class="block text-sm font-bold text-slate-800">{user.name_en || user.name_ar || user.username}</span>
                                  {#if user.name_ar && user.name_ar !== user.name_en}
                                    <span class="block text-xs text-slate-500" dir="rtl">{user.name_ar}</span>
                                  {/if}
                                  <span class="block text-xs text-slate-400">{user.employee_id}</span>
                                </button>
                              {:else}
                                <p class="px-4 py-3 text-sm text-slate-500">No eligible users found in the source branch.</p>
                              {/each}
                            </div>
                          {/if}
                        </div>
                      </div>
                    {:else}
                      <p class="mt-5 text-sm font-medium text-emerald-700">
                        The employee is not assigned as the source branch's Entry Task User.
                      </p>
                    {/if}

                    <div class="mt-6 flex flex-wrap items-center gap-3">
                      <button
                        type="button"
                        on:click={() => {
                          transferStep = 4;
                          transferSaveError = "";
                          transferSaveSuccess = "";
                        }}
                        disabled={savingTransfer}
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
                      >Back</button>
                      <button
                        type="button"
                        on:click={openBoxClosureStep}
                        disabled={loadingBoxClosureHandoff || (isEntryTaskUser && !entryTaskReplacementUserId)}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white transition-colors hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300"
                      >{loadingBoxClosureHandoff ? "Loading..." : "Next"}</button>
                      {#if entryTaskError}<p class="text-sm font-medium text-red-600">{entryTaskError}</p>{/if}
                      {#if boxClosureError}<p class="text-sm font-medium text-red-600">{boxClosureError}</p>{/if}
                    </div>
                  </div>
                </div>
              {:else}
                <div class="flex items-start gap-4">
                  <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-sm font-bold text-white">6</div>
                  <div class="min-w-0 flex-1">
                    <h2 class="text-lg font-bold text-slate-900">Complete Box Closure Permission</h2>
                    <p class="mt-1 text-sm text-slate-500">Hand off the employee's source-branch closure permission.</p>
                    {#if hasSourceBoxClosurePermission}
                      <div class="mt-5 max-w-2xl">
                        <label for="box-closure-replacement" class="mb-2 block text-sm font-bold text-slate-700">Replace With</label>
                        <div class="relative">
                          <input id="box-closure-replacement" type="text" bind:value={boxClosureReplacementSearch}
                            on:input={() => { boxClosureReplacementUserId = ""; boxClosureReplacementListOpen = true; }}
                            on:focus={() => (boxClosureReplacementListOpen = true)}
                            placeholder="Search an eligible user from the source branch"
                            class="w-full rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200" />
                          {#if boxClosureReplacementListOpen}
                            <div class="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-slate-200 bg-white shadow-lg">
                              {#each filteredBoxClosureReplacementUsers as user (user.user_id)}
                                <button type="button" on:click={() => selectBoxClosureReplacementUser(user)} class="block w-full border-b border-slate-100 px-4 py-3 text-left hover:bg-emerald-50">
                                  <span class="block text-sm font-bold text-slate-800">{user.name_en || user.name_ar || user.username}</span>
                                  {#if user.name_ar && user.name_ar !== user.name_en}<span class="block text-xs text-slate-500" dir="rtl">{user.name_ar}</span>{/if}
                                  <span class="block text-xs text-slate-400">{user.employee_id}</span>
                                </button>
                              {:else}<p class="px-4 py-3 text-sm text-slate-500">No eligible users found in the source branch.</p>{/each}
                            </div>
                          {/if}
                        </div>
                      </div>
                    {:else if hasAllBranchesBoxClosurePermission}
                      <p class="mt-5 text-sm font-medium text-blue-700">The employee has All Branches permission. It is not changed by this branch transfer.</p>
                    {:else}
                      <p class="mt-5 text-sm font-medium text-emerald-700">No source-branch Complete Box Closure permission needs reassignment.</p>
                    {/if}
                    <div class="mt-6 flex flex-wrap items-center gap-3">
                      <button type="button" on:click={() => { transferStep = 5; transferSaveError = ""; }} disabled={savingTransfer}
                        class="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100">Back</button>
                      <button type="button" on:click={saveEmployeeTransfer}
                        disabled={savingTransfer || (hasSourceBoxClosurePermission && !boxClosureReplacementUserId)}
                        class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300">{savingTransfer ? "Saving..." : "Save Transfer"}</button>
                      {#if transferSaveSuccess}<p class="text-sm font-medium text-emerald-700">{transferSaveSuccess}</p>{/if}
                      {#if transferSaveError}<p class="text-sm font-medium text-red-600">{transferSaveError}</p>{/if}
                      {#if boxClosureError}<p class="text-sm font-medium text-red-600">{boxClosureError}</p>{/if}
                    </div>
                  </div>
                </div>
              {/if}
            </div>
          {/if}
        </div>
      {/if}
    </div>
  </div>
  {/if}
</div>

{#if showCreateInsuranceCompany}
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-4"
  >
    <div class="w-full max-w-md rounded-2xl bg-white p-6 shadow-2xl">
      <h3 class="text-lg font-bold text-slate-900">Create Insurance Company</h3>
      <div class="mt-5 space-y-4">
        <div>
          <label
            for="insurance-company-name-en"
            class="mb-2 block text-sm font-bold text-slate-700"
            >English Name</label
          >
          <input
            id="insurance-company-name-en"
            type="text"
            bind:value={newInsuranceCompanyNameEn}
            class="w-full rounded-xl border border-slate-300 px-4 py-3 text-sm outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
          />
        </div>
        <div>
          <label
            for="insurance-company-name-ar"
            class="mb-2 block text-sm font-bold text-slate-700"
            >Arabic Name</label
          >
          <input
            id="insurance-company-name-ar"
            type="text"
            dir="rtl"
            bind:value={newInsuranceCompanyNameAr}
            class="w-full rounded-xl border border-slate-300 px-4 py-3 text-sm outline-none focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200"
          />
        </div>
      </div>
      <div class="mt-6 flex justify-end gap-3">
        <button
          type="button"
          disabled={creatingInsuranceCompany}
          class="rounded-xl border border-slate-300 px-5 py-3 text-sm font-bold text-slate-700 hover:bg-slate-100"
          on:click={() => (showCreateInsuranceCompany = false)}>Cancel</button
        >
        <button
          type="button"
          disabled={creatingInsuranceCompany}
          class="rounded-xl bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700 disabled:opacity-50"
          on:click={createInsuranceCompany}
          >{creatingInsuranceCompany ? "Creating..." : "Create Company"}</button
        >
      </div>
    </div>
  </div>
{/if}
