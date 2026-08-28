import { LightningElement, api, track } from "lwc";
import getPayerAccounts from "@salesforce/apex/InvoiceListController.getPayerAccounts";
import getInvoicesByPayerAccountId from "@salesforce/apex/InvoiceListController.getInvoicesByPayerAccountId";
import getSoldToAccountsByPayerAccountId from "@salesforce/apex/InvoiceListController.getSoldToAccountsByPayerAccountId";
import applyInvoicePaymentsJson from "@salesforce/apex/InvoiceListController.applyInvoicePaymentsJson";
import createPaymentIntent from "@salesforce/apex/InvoicePaymentController.createPaymentIntent";
import createPaymentIntentForElement from "@salesforce/apex/InvoicePaymentController.createPaymentIntentForElement";
import STRIPE_PUBLISHABLE_KEY from "@salesforce/label/c.Stripe_Publishable_Key";
import listCharges from "@salesforce/apex/InvoicePaymentController.listCharges";
import listCustomers from "@salesforce/apex/InvoicePaymentController.listCustomers";
// import createCustomer from "@salesforce/apex/InvoicePaymentControllerCTRL.createCustomer";
import createPaymentMethodForCustomer from "@salesforce/apex/InvoicePaymentController.createPaymentMethodForCustomer";
import listAllPaymentMethods from "@salesforce/apex/InvoicePaymentController.listAllPaymentMethods";
import getCustomerPaymentMethods from "@salesforce/apex/InvoicePaymentController.getCustomerPaymentMethods";
import getOrCreateCustomerAndPaymentMethods from "@salesforce/apex/InvoicePaymentController.getOrCreateCustomerAndPaymentMethods";
import syncPaymentCards from "@salesforce/apex/InvoicePaymentController.syncPaymentCards";
import recordPayment from "@salesforce/apex/InvoicePaymentController.recordPayment";

const PAYMENT_PAYLOAD_KEY = "invoiceListPaymentPayload";

export default class ChronarpayPaymentApp extends LightningElement {
  @track payerAccounts = [];
  @track selectedAccountId = "";
  @track selectedAccountNumber = "";
  @track soldToAccounts = [];
  @track selectedSoldToAccountId = "ALL";
  @track allInvoices = [];
  @track filteredInvoices = [];
  @track currentStep = "dashboard"; // 'dashboard' or 'payment'
  @track statusFilter = "Open";
  @track isProcessing = false;
  @track currentPage = 1;
  @track pageSize = 10;
  @track transactionPage = 1;
  @track transactionPageSize = 10;
  @track paymentStatus = null; // 'success', 'cancel', or null
  @track showNewInvoiceModal = false;
  @track showPaymentMethodModal = false;
  @track stripeTransactions = [];
  @track customers = [];
  @track paymentMethods = [];
  @track isLoadingPaymentMethods = false;
  @track selectedCustomerId = "";
  @track searchTerm = "";
  @track showCustomerForm = false;
  @track isCreatingCustomer = false;
  @track isCreatingPaymentMethod = false;
  @track customerError = "";
  @track customerSuccess = "";
  @track paymentMode = "existing";
  @track selectedPaymentCustomerId = "";
  @track selectedPaymentMethodId = "";
  @track paymentError = "";
  @track stripeElementReady = false;
  @track stripeElementLoading = false;
  // Active Stripe Customer for the payment step (set when Pay is clicked)
  @track activeStripeCustomer = null;  // { id, name, email, isNewCustomer, accountName, accountNumber }
  @track isLoadingCustomer = false;
  @track activeCustomerPaymentMethods = []; // payment methods for the active customer only
  stripe;
  stripeElements;
  paymentElement;
  stripeClientSecret = "";
  pendingStripeElementInitialization = false;
  stripeRefreshTimer;
  stripeBridgeId;
  stripeBridgeCounter = 0;
  stripeBridgeRequests = new Map();
  boundStripeBridgeHandler;
  @track newInvoice = {
    billingDocumentNumber: "",
    referenceNumber: "",
    accountNumber: "",
    currencyKey: "USD",
    totalAmount: "",
    status: "Open",
    documentDate: "",
    dueDate: ""
  };
  customerForm = {
    email: "",
    name: "",
    description: ""
  };
  paymentMethodForm = {
    customerId: "",
    name: "",
    stripeToken: ""
  };

  connectedCallback() {
    // Stripe.js itself runs in the privileged LWR x-oasis-script context.
    // This LWC talks to that context only through DOM CustomEvents.
    this.stripeBridgeId = `invoice-list-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    this.boundStripeBridgeHandler = this.handleStripeBridgeResponse.bind(this);
    window.addEventListener(
      "stripe-lwr-response",
      this.boundStripeBridgeHandler
    );

    this.checkPaymentStatus();
    this.loadPayerAccounts();
    this.loadCustomers();
    this.loadAllPaymentMethods();
  }

  disconnectedCallback() {
    if (this.boundStripeBridgeHandler) {
      window.removeEventListener(
        "stripe-lwr-response",
        this.boundStripeBridgeHandler
      );
    }
    window.clearTimeout(this.stripeRefreshTimer);
    this.callStripeBridge("destroy", {}, 1500).catch(() => {});
    this.stripeBridgeRequests.forEach(({ reject, timer }) => {
      window.clearTimeout(timer);
      reject(
        new Error(
          "Stripe bridge request cancelled because the component was disconnected."
        )
      );
    });
    this.stripeBridgeRequests.clear();
  }

  renderedCallback() {
    if (
      this.isStepPayment &&
      this.isNewPaymentMode &&
      this.pendingStripeElementInitialization &&
      !this.stripeElementLoading
    ) {
      this.pendingStripeElementInitialization = false;
      this.initializeStripePaymentElement();
    }
  }

  accountStripeCustomerCache = new Map();

  async resolveStripeCustomerForAccount(accountId, forceRefresh = false) {
    if (!accountId) return null;
    if (!forceRefresh && this.accountStripeCustomerCache.has(accountId)) {
      return this.accountStripeCustomerCache.get(accountId);
    }
    try {
      const resultJson = await getOrCreateCustomerAndPaymentMethods({ accountId });
      const result = typeof resultJson === "string" ? JSON.parse(resultJson) : resultJson;
      const custObj = result.customer || {};
      const data = {
        customer: result.customer || null,
        customerId: custObj.id || "",
        paymentMethods: Array.isArray(result.paymentMethods) ? result.paymentMethods : [],
        accountName: result.accountName || "",
        accountNumber: result.accountNumber || "",
        salesOrganization: result.salesOrganization || "",
        email: result.email || custObj.email || "",
        phone: result.phone || custObj.phone || "",
        billingStreet: result.billingStreet || custObj.address?.line1 || "",
        billingCity: result.billingCity || custObj.address?.city || "",
        billingState: result.billingState || custObj.address?.state || "",
        billingPostalCode: result.billingPostalCode || custObj.address?.postal_code || "",
        billingCountry: result.billingCountry || custObj.address?.country || "US",
        address: custObj.address || {
          line1: result.billingStreet || "",
          city: result.billingCity || "",
          state: result.billingState || "",
          postal_code: result.billingPostalCode || "",
          country: result.billingCountry || "US"
        }
      };
      this.accountStripeCustomerCache.set(accountId, data);
      return data;
    } catch (e) {
      console.warn("Could not resolve Stripe customer for account:", e);
      return null;
    }
  }

  async loadStripeTransactions() {
    this.isProcessing = true;
    try {
      if (!this.customers || !this.customers.length) {
        await this.loadCustomers();
      }

      let customerIdToFilter = null;
      if (this.selectedAccountId) {
        const custData = await this.resolveStripeCustomerForAccount(this.selectedAccountId);
        if (custData && custData.customerId) {
          customerIdToFilter = custData.customerId;
        }
      }

      const result = await listCharges({
        limitUsed: 100,
        customerId: customerIdToFilter || undefined
      });
      const parsed = typeof result === "string" ? JSON.parse(result) : result;
      const data = parsed && parsed.data ? parsed.data : [];
      this.stripeTransactions = (data || []).map((tx) => {
        const amountVal = tx.amount != null ? tx.amount / 100 : 0;
        const created = tx.created ? new Date(tx.created * 1000) : null;

        // Payment method details
        let pmDisplay = "-";
        if (tx.payment_method_details && tx.payment_method_details.card) {
          const card = tx.payment_method_details.card;
          const brand = card.brand
            ? card.brand.charAt(0).toUpperCase() + card.brand.slice(1)
            : "Card";
          pmDisplay = brand + (card.last4 ? " •••• " + card.last4 : "");
        } else if (
          tx.payment_method_details &&
          tx.payment_method_details.us_bank_account
        ) {
          const bank =
            tx.payment_method_details.us_bank_account.bank_name || "Bank";
          const last4 = tx.payment_method_details.us_bank_account.last4 || "";
          pmDisplay = bank + (last4 ? " •••• " + last4 : "");
        } else if (
          tx.payment_method_details &&
          tx.payment_method_details.type
        ) {
          pmDisplay =
            tx.payment_method_details.type.charAt(0).toUpperCase() +
            tx.payment_method_details.type.slice(1);
        } else if (tx.source && tx.source.brand) {
          const brand =
            tx.source.brand.charAt(0).toUpperCase() + tx.source.brand.slice(1);
          pmDisplay =
            brand + (tx.source.last4 ? " •••• " + tx.source.last4 : "");
        }

        // Customer display - matching the payment methods page resolution
        const customerId =
          typeof tx.customer === "string" ? tx.customer : tx.customer?.id;
        const customerObj =
          this.customers && this.customers.find((c) => c.id === customerId);

        let customerDisplay = "-";
        if (customerObj && customerObj.name) {
          customerDisplay = customerObj.name;
        } else if (tx.billing_details && tx.billing_details.name) {
          customerDisplay = tx.billing_details.name;
        } else if (tx.billing_details && tx.billing_details.email) {
          customerDisplay = tx.billing_details.email;
        } else if (tx.receipt_email) {
          customerDisplay = tx.receipt_email;
        } else if (customerId) {
          customerDisplay = customerId;
        }

        // Date (date-time format)
        const createdDisplay = created
          ? created.toLocaleString("en-US", {
              month: "short",
              day: "numeric",
              year: "numeric",
              hour: "numeric",
              minute: "2-digit",
              hour12: true
            })
          : "-";

        // Refunded Date (date-time format)
        let refundedDateDisplay = "-";
        if (tx.refunds && tx.refunds.data && tx.refunds.data.length > 0) {
          const refDate = tx.refunds.data[0].created
            ? new Date(tx.refunds.data[0].created * 1000)
            : null;
          refundedDateDisplay = refDate
            ? refDate.toLocaleString("en-US", {
                month: "short",
                day: "numeric",
                year: "numeric",
                hour: "numeric",
                minute: "2-digit",
                hour12: true
              })
            : "-";
        } else if (tx.refunded) {
          refundedDateDisplay = "Refunded";
        }

        // Decline reason
        let declineReasonDisplay = "-";
        if (tx.failure_message) {
          declineReasonDisplay = tx.failure_message;
        } else if (tx.status === "succeeded") {
          declineReasonDisplay = "-";
        } else if (
          tx.outcome &&
          (tx.outcome.seller_message || tx.outcome.reason)
        ) {
          declineReasonDisplay = tx.outcome.seller_message || tx.outcome.reason;
        } else if (tx.failure_code) {
          declineReasonDisplay = tx.failure_code;
        } else if (tx.status === "failed") {
          declineReasonDisplay = "Declined";
        }

        const statusVal = tx.status || (tx.paid ? "succeeded" : "failed");
        let statusBadgeClass = "status-badge ";
        if (statusVal === "succeeded" || statusVal === "paid") {
          statusBadgeClass += "paid";
        } else if (statusVal === "failed") {
          statusBadgeClass += "open";
        } else if (statusVal === "refunded") {
          statusBadgeClass += "refunded";
        } else {
          statusBadgeClass += "credit";
        }

        const currencyStr = (tx.currency || "usd").toUpperCase();
        const currencySymbol =
          currencyStr === "USD"
            ? "$"
            : currencyStr === "EUR"
              ? "€"
              : currencyStr === "GBP"
                ? "£"
                : currencyStr + " ";

        return {
          id: tx.id,
          status: statusVal,
          statusBadgeClass: statusBadgeClass,
          paid: !!tx.paid,
          amount: amountVal,
          amountDisplay: amountVal.toFixed(2),
          currency: currencyStr,
          currencySymbol: currencySymbol,
          amountFormatted: currencySymbol + amountVal.toFixed(2),
          paymentMethod: pmDisplay,
          description: tx.description || tx.statement_descriptor || "-",
          customer: customerDisplay,
          createdDisplay: createdDisplay,
          refundedDate: refundedDateDisplay,
          declineReason: declineReasonDisplay,
          receiptUrl: tx.receipt_url || "",
          selected: false
        };
      });
      this.transactionPage = 1;
    } catch (e) {
      console.error("Failed to parse Stripe charges response", e);
      this.stripeTransactions = [];
    } finally {
      this.isProcessing = false;
    }
  }

  loadPayerAccounts() {
    this.isProcessing = true;
    getPayerAccounts()
      .then((accounts) => {
        this.payerAccounts = accounts || [];
        if (this.payerAccounts.length > 0) {
          const matchingAccount = this.payerAccounts.find(
            (acc) => acc.accountId === this.selectedAccountId
          );
          if (!this.selectedAccountId || !matchingAccount) {
            this.selectedAccountId = this.payerAccounts[0].accountId;
            this.selectedAccountNumber = this.payerAccounts[0].accountNumber;
            this.selectedSalesOrganization =
              this.payerAccounts[0].salesOrganization;
          } else {
            this.selectedAccountNumber = matchingAccount.accountNumber;
          }
          return this.loadInvoicesForSelectedAccount();
        }
        return null;
      })
      .catch((error) => {
        console.error("Error loading payer accounts:", error);
        this.isProcessing = false;
      })
      .finally(() => {
        this.isProcessing = false;
      });
  }

  loadInvoicesForSelectedAccount() {
    if (!this.selectedAccountId) {
      this.allInvoices = [];
      this.filteredInvoices = [];
      this.soldToAccounts = [];
      return Promise.resolve();
    }

    this.isProcessing = true;

    // Load Sold To accounts associated with the selected Payer Account
    getSoldToAccountsByPayerAccountId({
      payerAccountId: this.selectedAccountId
    })
      .then((soldTos) => {
        this.soldToAccounts = soldTos || [];
      })
      .catch((err) => {
        console.warn("Error loading sold to accounts for payer account:", err);
        this.soldToAccounts = [];
      });

    return getInvoicesByPayerAccountId({
      payerAccountId: this.selectedAccountId
    })
      .then((invoices) => {
        this.allInvoices = (invoices || []).map((inv, index) =>
          this.normalizeInvoice(inv, index)
        );
        this.filterInvoicesByAccount();
      })
      .catch((error) => {
        console.error("Error loading invoices for payer account:", error);
        this.allInvoices = [];
        this.filteredInvoices = [];
      })
      .finally(() => {
        this.isProcessing = false;
      });
  }

  getPaymentStatusFromUrl() {
    try {
      const currentUrl = new URL(window.location.href);
      let params = new URLSearchParams(currentUrl.search);
      if (!params.has("payment_status") && !params.has("c__payment_status")) {
        const hash = currentUrl.hash || "";
        const queryIndex = hash.indexOf("?");
        if (queryIndex !== -1) {
          params = new URLSearchParams(hash.slice(queryIndex + 1));
        }
      }
      return params;
    } catch (error) {
      console.error("Error parsing URL parameters:", error);
      return new URLSearchParams();
    }
  }

  async checkPaymentStatus() {
    const urlParams = this.getPaymentStatusFromUrl();
    const status =
      urlParams.get("c__payment_status") || urlParams.get("payment_status");
    const clientSecret = urlParams.get("payment_intent_client_secret");

    if (status === "stripe_return" && clientSecret) {
      this.isProcessing = true;
      let storedPayload = sessionStorage.getItem(this.paymentStorageKey) || localStorage.getItem(this.paymentStorageKey);
      let returnAccountId = this.selectedAccountId;
      if (storedPayload) {
        try {
          const parsedPayload = JSON.parse(storedPayload);
          returnAccountId = parsedPayload.payerAccountId || returnAccountId;
        } catch {
          // ignore
        }
      }

      try {
        if (
          !STRIPE_PUBLISHABLE_KEY ||
          !STRIPE_PUBLISHABLE_KEY.startsWith("pk_")
        ) {
          throw new Error("Stripe publishable key is not configured.");
        }
        const bridgeResult = await this.callStripeBridge("retrieve", {
          publishableKey: STRIPE_PUBLISHABLE_KEY,
          clientSecret
        });
        const paymentIntent = bridgeResult?.paymentIntent;
        const piId = paymentIntent?.id || "";
        const piPm = typeof paymentIntent?.payment_method === "string"
          ? paymentIntent.payment_method
          : paymentIntent?.payment_method?.id || "";
        const piAmount = paymentIntent?.amount ? paymentIntent.amount / 100 : 0;
        const piAmountReceived = paymentIntent?.amount_received
          ? paymentIntent.amount_received / 100
          : (paymentIntent?.status === "succeeded" ? piAmount : 0);
        const piCurrency = paymentIntent?.currency ? paymentIntent.currency.toUpperCase() : "USD";

        if (paymentIntent?.status === "succeeded") {
          let syncCustId = "";
          if (storedPayload) {
            try {
              const parsedPayload = JSON.parse(storedPayload);
              syncCustId = parsedPayload.stripeCustomerId || "";
            } catch {
              // ignore
            }
          }
          if (!syncCustId) {
            syncCustId = this.selectedPaymentCustomerId;
          }

          // 1. First sync cards so Payment_Method__c is created in Salesforce
          if (returnAccountId && syncCustId) {
            try {
              await syncPaymentCards({
                accountId: returnAccountId,
                customerId: syncCustId
              });
            } catch (syncErr) {
              console.warn("Payment card sync on return failed:", syncErr);
            }
          }

          // 2. Then record the SF Payment__c record with the linked Payment_Method__c
          if (returnAccountId) {
            await this.recordPaymentSafely({
              accountId: returnAccountId,
              amount: piAmount,
              amountReceived: piAmountReceived,
              currencyCode: piCurrency,
              paymentIntentId: piId,
              paymentMethodId: piPm,
              status: "Paid",
              failureReason: ""
            });
          }
          this.paymentStatus = "success";
          this.handleSuccessfulPayment(true);
        } else {
          if (returnAccountId) {
            await this.recordPaymentSafely({
              accountId: returnAccountId,
              amount: piAmount,
              amountReceived: 0,
              currencyCode: piCurrency,
              paymentIntentId: piId,
              paymentMethodId: piPm,
              status: paymentIntent?.status === "canceled" ? "Canceled" : "Failed",
              failureReason: `PaymentIntent returned status: ${paymentIntent?.status || "unknown"}`
            });
          }
          this.paymentStatus = "cancel";
          sessionStorage.removeItem(this.paymentStorageKey);
          localStorage.removeItem(this.paymentStorageKey);
          this.isProcessing = false;
        }
      } catch (error) {
        console.error("Unable to verify returned Stripe PaymentIntent:", error);
        if (returnAccountId) {
          await this.recordPaymentSafely({
            accountId: returnAccountId,
            amount: 0,
            amountReceived: 0,
            currencyCode: "USD",
            paymentIntentId: "",
            paymentMethodId: "",
            status: "Failed",
            failureReason: (error.message || "Unable to verify Stripe payment.").substring(0, 255)
          });
        }
        this.paymentStatus = "cancel";
        this.paymentError = error.message || "Unable to verify Stripe payment.";
        this.isProcessing = false;
      }

      const url = new URL(window.location.href);
      [
        "c__payment_status",
        "payment_status",
        "payment_intent",
        "payment_intent_client_secret",
        "redirect_status"
      ].forEach((name) => url.searchParams.delete(name));
      window.history.replaceState({}, document.title, url.toString());
      return;
    }

    // Keep backward compatibility with the earlier Checkout Session return flags.
    if (status === "success" || status === "cancel") {
      this.paymentStatus = status;
      if (status === "success") {
        this.handleSuccessfulPayment();
      }

      const url = new URL(window.location.href);
      url.searchParams.delete("c__payment_status");
      url.searchParams.delete("payment_status");
      window.history.replaceState({}, document.title, url.toString());
    }
  }

  handleDismissPaymentStatus() {
    this.paymentStatus = null;
  }

  // parseCSV(csvText) {
  //   const lines = csvText.split(/\r?\n/);
  //   if (lines.length === 0) return [];
  //   const headers = lines[0].split(",").map((h) => h.trim().toLowerCase());

  //   const getIdx = (name, fallback) => {
  //     const index = headers.indexOf(name.toLowerCase());
  //     return index !== -1 ? index : fallback;
  //   };

  //   const statusIdx = getIdx("status", 0);
  //   const refIdx = getIdx("reference number", 1);
  //   const docIdx = getIdx("billing document number", 2);
  //   const dateIdx = getIdx("document date", 3);

  //   let totalIdx = headers.findIndex((h) => h.includes("total amount"));
  //   if (totalIdx === -1) totalIdx = 4;
  //   let paidIdx = headers.findIndex((h) => h.includes("paid amount"));
  //   if (paidIdx === -1) paidIdx = 5;
  //   let openIdx = headers.findIndex((h) => h.includes("open amount"));
  //   if (openIdx === -1) openIdx = 6;

  //   const dueIdx = getIdx("due date", 7);
  //   const soldIdx = getIdx("soldto number", 8);
  //   const accIdx = getIdx("account number", 9);
  //   let currencyIdx = headers.indexOf("currencykey");
  //   if (currencyIdx === -1) {
  //     currencyIdx = headers.findIndex(
  //       (h) => h.includes("currency") && !h.includes("amount")
  //     );
  //   }

  //   const records = [];
  //   for (let i = 1; i < lines.length; i++) {
  //     const line = lines[i].trim();
  //     if (!line) continue;
  //     const cells = line.split(",");

  //     const total = parseFloat(cells[totalIdx]?.trim()) || 0.0;
  //     const paid = parseFloat(cells[paidIdx]?.trim()) || 0.0;
  //     const open = parseFloat(cells[openIdx]?.trim()) || 0.0;
  //     const docNum = cells[docIdx]?.trim() || "";
  //     const status = cells[statusIdx]?.trim() || "Open";
  //     const currencyKeyVal =
  //       currencyIdx !== -1 ? cells[currencyIdx]?.trim() : "USD";

  //     const record = {
  //       status: status,
  //       referenceNumber: cells[refIdx]?.trim() || "",
  //       billingDocumentNumber: docNum,
  //       documentDate: cells[dateIdx]?.trim() || "",
  //       totalAmount: total,
  //       paidAmount: paid,
  //       openAmount: open,
  //       dueDate: cells[dueIdx]?.trim() || "",
  //       soldToNumber: cells[soldIdx]?.trim() || "",
  //       accountNumber: cells[accIdx]?.trim() || "",
  //       currencyKey: currencyKeyVal,
  //       currencySymbol:
  //         currencyKeyVal === "EUR" ? "€" : currencyKeyVal === "GBP" ? "£" : "$",
  //       selected: false,
  //       key: docNum + "-" + i,

  //       // Formatting fields
  //       formattedTotal: total.toLocaleString("en-US", {
  //         minimumFractionDigits: 2,
  //         maximumFractionDigits: 2
  //       }),
  //       formattedPaid: paid.toLocaleString("en-US", {
  //         minimumFractionDigits: 2,
  //         maximumFractionDigits: 2
  //       }),
  //       formattedOpen: open.toLocaleString("en-US", {
  //         minimumFractionDigits: 2,
  //         maximumFractionDigits: 2
  //       }),
  //       formattedOpenAbs: Math.abs(open).toLocaleString("en-US", {
  //         minimumFractionDigits: 2,
  //         maximumFractionDigits: 2
  //       }),
  //       isPaid: status === "Paid" || open === 0,
  //       isCredit: open < 0,
  //       isPositiveOpen: open > 0,
  //       statusBadgeClass:
  //         "status-badge " + (open < 0 ? "credit" : status.toLowerCase()),

  //       // Step 2 payment value
  //       payAmount: open > 0 ? open : 0
  //     };
  //     records.push(record);
  //   }
  //   return records;
  // }

  normalizeInvoice(inv, index) {
    const openAmount = inv.openAmount != null ? inv.openAmount : 0;
    const totalAmount = inv.totalAmount != null ? inv.totalAmount : 0;
    const paidAmount = inv.paidAmount != null ? inv.paidAmount : 0;
    const currencyKey = inv.currencyKey ? inv.currencyKey.toUpperCase() : "USD";
    const docNum = inv.billingDocumentNumber || "";

    return {
      invoiceId: inv.invoiceId,
      billingDocumentNumber: docNum,
      referenceNumber: inv.referenceNumber,
      documentDate: inv.documentDate || "",
      dueDate: inv.dueDate || "",
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      openAmount: openAmount,
      currencyKey: currencyKey,
      currencySymbol:
        currencyKey === "EUR" ? "€" : currencyKey === "GBP" ? "£" : "$",
      formattedTotal: totalAmount.toLocaleString("en-US", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }),
      formattedPaid: paidAmount.toLocaleString("en-US", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }),
      formattedOpen: openAmount.toLocaleString("en-US", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }),
      formattedOpenAbs: Math.abs(openAmount).toLocaleString("en-US", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      }),
      selected: false,
      key: docNum + "-" + index,
      isPaid: openAmount === 0,
      isCredit: openAmount < 0,
      isPositiveOpen: openAmount > 0,
      statusBadgeClass:
        "status-badge " +
        (openAmount < 0 ? "credit" : openAmount === 0 ? "paid" : "open"),
      payAmount: openAmount > 0 ? openAmount : 0,
      accountId: inv.accountId,
      accountNumber: inv.accountNumber,
      soldToAccountId: inv.soldToAccountId,
      soldToAccountNumber: inv.soldToAccountNumber,
      soldToAccountName: inv.soldToAccountName
    };
  }

  get accountOptions() {
    return (this.payerAccounts || []).map((acc) => ({
      label:
        acc.accountName +
        " - " +
        acc.accountNumber +
        " (" +
        acc.salesOrganization +
        ")",
      value: acc.accountId,
      selected: acc.accountId === this.selectedAccountId
    }));
  }

  get soldToAccountOptions() {
    const options = [
      {
        label: "All Accounts",
        value: "ALL",
        selected:
          this.selectedSoldToAccountId === "ALL" ||
          !this.selectedSoldToAccountId
      }
    ];

    (this.soldToAccounts || []).forEach((acc) => {
      const parts = [];
      if (acc.accountName) parts.push(acc.accountName);
      if (acc.accountNumber) parts.push(acc.accountNumber);
      let label = parts.join(" - ");
      if (acc.salesOrganization) {
        label += ` (${acc.salesOrganization})`;
      }
      options.push({
        label: label.trim() || acc.accountId,
        value: acc.accountId,
        selected: acc.accountId === this.selectedSoldToAccountId
      });
    });

    return options;
  }

  filterInvoicesByAccount() {
    let accountInvoices = this.allInvoices.filter(
      (inv) => inv.accountId === this.selectedAccountId
    );

    // Filter by Sold To Account if a specific Sold To is selected
    if (
      this.selectedSoldToAccountId &&
      this.selectedSoldToAccountId !== "ALL"
    ) {
      accountInvoices = accountInvoices.filter(
        (inv) => inv.soldToAccountId === this.selectedSoldToAccountId
      );
    }

    this.filteredInvoices = accountInvoices.filter((inv) => {
      if (this.statusFilter === "Open") {
        return !inv.isPaid;
      } else if (this.statusFilter === "Paid") {
        return inv.isPaid;
      }
      return true;
    });
  }

  get selectedAccountLabel() {
    const account = this.payerAccounts.find(
      (acc) => acc.accountId === this.selectedAccountId
    );
    if (!account) return "";
    return `${account.accountName} - ${account.accountNumber} (${account.salesOrganization ? account.salesOrganization : ""})`;
  }

  // Handlers
  handleAccountChange(event) {
    const selectedId = event.target.value;
    this.selectedAccountId = selectedId;
    this.selectedSoldToAccountId = "ALL";
    const account = this.payerAccounts.find(
      (acc) => acc.accountId === selectedId
    );
    this.selectedAccountNumber = account ? account.accountNumber : "";
    this.currentPage = 1;
    this.transactionPage = 1;

    // Load data based on current step
    this.loadInvoicesForSelectedAccount();
    if (this.isStepTransactions) {
      this.loadStripeTransactions();
    } else if (this.isStepCustomers) {
      this.loadAllPaymentMethods();
    }
  }

  handleSoldToAccountChange(event) {
    this.selectedSoldToAccountId = event.target.value;
    this.currentPage = 1;
    this.filterInvoicesByAccount();
  }

  handleStatusFilterChange(event) {
    this.statusFilter = event.target.value;
    this.currentPage = 1;
    this.filterInvoicesByAccount();
  }

  handleRowSelect(event) {
    const rowKey = event.target.dataset.id;
    const checked = event.target.checked;
    this.allInvoices = this.allInvoices.map((inv) => {
      if (inv.key === rowKey) {
        return { ...inv, selected: checked };
      }
      return inv;
    });
    this.filterInvoicesByAccount();
  }

  handleSelectAll(event) {
    const checked = event.target.checked;
    const visibleKeys = new Set(this.paginatedInvoices.map((inv) => inv.key));

    this.allInvoices = this.allInvoices.map((inv) => {
      if (visibleKeys.has(inv.key)) {
        return { ...inv, selected: checked };
      }
      return inv;
    });
    this.filterInvoicesByAccount();
  }

  handlePayAmountChange(event) {
    const rowKey = event.target.dataset.id;
    const value = parseFloat(event.target.value) || 0.0;
    this.allInvoices = this.allInvoices.map((inv) => {
      if (inv.key === rowKey) {
        return { ...inv, payAmount: value };
      }
      return inv;
    });
    this.filterInvoicesByAccount();
    if (this.isStepPayment && this.isNewPaymentMode) {
      this.scheduleStripeElementRefresh();
    }
  }

  handleRemoveInvoice(event) {
    const rowKey = event.target.dataset.id;
    this.allInvoices = this.allInvoices.map((inv) => {
      if (inv.key === rowKey) {
        return { ...inv, selected: false };
      }
      return inv;
    });
    this.filterInvoicesByAccount();
    if (this.isStepPayment && this.isNewPaymentMode) {
      this.scheduleStripeElementRefresh();
    }
  }

  // Pagination Actions
  handlePageClick(event) {
    this.currentPage = parseInt(event.target.dataset.page, 10);
  }

  handlePrevPage() {
    if (this.currentPage > 1) {
      this.currentPage--;
    }
  }

  handleNextPage() {
    if (this.currentPage < this.totalPages) {
      this.currentPage++;
    }
  }

  handlePageSizeChange(event) {
    this.pageSize = parseInt(event.target.value, 10);
    this.currentPage = 1;
  }

  handleTransactionPageClick(event) {
    this.transactionPage = parseInt(event.target.dataset.page, 10);
  }

  handleTransactionPrevPage() {
    if (this.transactionPage > 1) {
      this.transactionPage--;
    }
  }

  handleTransactionNextPage() {
    if (this.transactionPage < this.totalTransactionPages) {
      this.transactionPage++;
    }
  }

  handleTransactionPageSizeChange(event) {
    this.transactionPageSize = parseInt(event.target.value, 10);
    this.transactionPage = 1;
  }

  // handleTransactionSelectAll(event) {
  //   const checked = event.target.checked;
  //   const pageIds = new Set(
  //     this.paginatedStripeTransactions.map((tx) => tx.id)
  //   );
  //   this.stripeTransactions = this.stripeTransactions.map((tx) => {
  //     if (pageIds.has(tx.id)) {
  //       return { ...tx, selected: checked };
  //     }
  //     return tx;
  //   });
  // }

  // handleTransactionRowSelect(event) {
  //   const id = event.target.dataset.id;
  //   const checked = event.target.checked;
  //   this.stripeTransactions = this.stripeTransactions.map((tx) => {
  //     return tx.id === id ? { ...tx, selected: checked } : tx;
  //   });
  // }

  // Step navigation
  navigateToDashboard() {
    this.currentStep = "dashboard";
  }

  navigateToTransactions() {
    this.currentStep = "transactions";
    // load transactions when navigating to the tab
    this.loadStripeTransactions();
  }

  navigateToCustomers() {
    this.currentStep = "customers";
    this.loadCustomers();
    this.loadAllPaymentMethods();
  }

  async goToPaymentStep() {
    // Determine the Account ID from the selected invoices.
    // All invoices in the session should belong to one account (the filtered account).
    const targetAccountId = this.selectedAccountId;
    if (!targetAccountId) {
      this.paymentError = "No account selected. Please select an account before paying.";
      return;
    }

    this.isLoadingCustomer = true;
    this.paymentError = "";
    this.activeStripeCustomer = null;
    this.activeCustomerPaymentMethods = [];
    this.selectedPaymentCustomerId = "";
    this.selectedPaymentMethodId = "";
    this.currentStep = "payment";

    try {
      const resultJson = await getOrCreateCustomerAndPaymentMethods({ accountId: targetAccountId });
      const result = typeof resultJson === "string" ? JSON.parse(resultJson) : resultJson;

      const customer = result.customer || {};
      const paymentMethodsRaw = Array.isArray(result.paymentMethods) ? result.paymentMethods : [];

      // Store the active Stripe customer details including address from customer information
      const custAddress = customer.address || {};
      const billingStreet = result.billingStreet || custAddress.line1 || "";
      const billingCity = result.billingCity || custAddress.city || "";
      const billingState = result.billingState || custAddress.state || "";
      const billingPostalCode = result.billingPostalCode || custAddress.postal_code || "";
      const billingCountry = result.billingCountry || custAddress.country || "US";
      const customerPhone = result.phone || customer.phone || "";
      const customerEmail = result.email || customer.email || "";

      this.activeStripeCustomer = {
        id: customer.id || "",
        name: customer.name || result.accountName || "",
        email: customerEmail,
        phone: customerPhone,
        description: customer.description || "",
        isNewCustomer: !!result.isNewCustomer,
        accountName: result.accountName || "",
        accountNumber: result.accountNumber || "",
        salesOrganization: result.salesOrganization || "",
        billingStreet,
        billingCity,
        billingState,
        billingPostalCode,
        billingCountry,
        address: {
          line1: billingStreet,
          line2: custAddress.line2 || "",
          city: billingCity,
          state: billingState,
          postal_code: billingPostalCode,
          country: billingCountry
        }
      };

      // Lock the payment step to this customer
      this.selectedPaymentCustomerId = customer.id || "";

      // Map payment methods to the internal format used by paymentMethodOptions
      this.activeCustomerPaymentMethods = paymentMethodsRaw.map((method) => ({
        id: method.id,
        type: method.type,
        brand: method.card && method.card.brand ? method.card.brand.toUpperCase() : "CARD",
        last4: method.card ? method.card.last4 : "****",
        expMonth: method.card ? method.card.exp_month : "—",
        expYear: method.card ? method.card.exp_year : "—",
        stripeCustomerId: customer.id || "",
        customerName: method.billing_details && method.billing_details.name
          ? method.billing_details.name
          : (customer.name || "")
      }));

      if (this.activeCustomerPaymentMethods.length > 0) {
        // Saved cards available — default to existing card mode
        this.paymentMode = "existing";
        this.selectedPaymentMethodId = this.activeCustomerPaymentMethods[0].id;
        this.destroyStripePaymentElement();
      } else {
        // No saved cards — automatically switch to new card mode
        this.paymentMode = "new";
        this.selectedPaymentMethodId = "";
        this.requestStripeElementRefresh();
      }
    } catch (error) {
      this.paymentError =
        error.body?.message ||
        error.message ||
        "Failed to load Stripe customer for this account. Please try again.";
      // Remain on payment step but show the error
    } finally {
      this.isLoadingCustomer = false;
    }
  }

  // New Invoice Modal Actions
  getTodayDateString(offsetDays = 0) {
    const d = new Date();
    if (offsetDays > 0) {
      d.setDate(d.getDate() + offsetDays);
    }
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  // handleNewInvoiceClick() {
  //   this.newInvoice = {
  //     billingDocumentNumber: "",
  //     referenceNumber: "",
  //     accountId: this.selectedAccountId,
  //     accountNumber: this.selectedAccountNumber,
  //     currencyKey: this.accountCurrency,
  //     totalAmount: "",
  //     status: "Open",
  //     documentDate: this.getTodayDateString(0),
  //     dueDate: this.getTodayDateString(30)
  //   };
  //   this.showNewInvoiceModal = true;
  // }

  handleCloseModal() {
    this.showNewInvoiceModal = false;
  }

  handleInputChange(event) {
    const fieldName = event.target.name;
    const value = event.target.value;
    if (fieldName === "accountId") {
      const account = this.payerAccounts.find((acc) => acc.accountId === value);
      this.newInvoice = {
        ...this.newInvoice,
        accountId: value,
        accountNumber: account ? account.accountNumber : "",
        salesOrganization: account ? account.salesOrganization : ""
      };
      return;
    }
    this.newInvoice = {
      ...this.newInvoice,
      [fieldName]: value
    };
  }

  // handleSaveInvoice() {
  //   const allValid = [
  //     ...this.template.querySelectorAll("lightning-input, lightning-combobox")
  //   ].reduce((validSoFar, inputFields) => {
  //     inputFields.reportValidity();
  //     return validSoFar && inputFields.checkValidity();
  //   }, true);

  //   if (!allValid) {
  //     return;
  //   }

  //   const total = parseFloat(this.newInvoice.totalAmount) || 0.0;
  //   let paid = 0.0;
  //   let open = total;
  //   let statusVal = this.newInvoice.status;

  //   if (statusVal === "Credit") {
  //     open = -Math.abs(total);
  //     paid = 0.0;
  //   }

  //   const formatDateStr = (ymd) => {
  //     if (!ymd) return "";
  //     const parts = ymd.split("-");
  //     if (parts.length === 3) {
  //       return `${parts[2]}/${parts[1]}/${parts[0]}`;
  //     }
  //     return ymd;
  //   };

  //   const docNum = this.newInvoice.billingDocumentNumber;
  //   const currencyKeyVal = this.newInvoice.currencyKey.toUpperCase();

  //   const newRecord = {
  //     invoiceId: null,
  //     referenceNumber: this.newInvoice.referenceNumber,
  //     billingDocumentNumber: docNum,
  //     documentDate: formatDateStr(this.newInvoice.documentDate),
  //     totalAmount: Math.abs(total),
  //     paidAmount: paid,
  //     openAmount: open,
  //     dueDate: formatDateStr(this.newInvoice.dueDate),
  //     soldToNumber: "",
  //     accountId: this.newInvoice.accountId,
  //     accountNumber: this.newInvoice.accountNumber,
  //     currencyKey: currencyKeyVal,
  //     currencySymbol:
  //       currencyKeyVal === "EUR" ? "€" : currencyKeyVal === "GBP" ? "£" : "$",
  //     selected: false,
  //     key: docNum + "-" + Date.now(),

  //     formattedTotal: Math.abs(total).toLocaleString("en-US", {
  //       minimumFractionDigits: 2,
  //       maximumFractionDigits: 2
  //     }),
  //     formattedPaid: paid.toLocaleString("en-US", {
  //       minimumFractionDigits: 2,
  //       maximumFractionDigits: 2
  //     }),
  //     formattedOpen: open.toLocaleString("en-US", {
  //       minimumFractionDigits: 2,
  //       maximumFractionDigits: 2
  //     }),
  //     formattedOpenAbs: Math.abs(open).toLocaleString("en-US", {
  //       minimumFractionDigits: 2,
  //       maximumFractionDigits: 2
  //     }),
  //     isPaid: statusVal === "Paid" || open === 0,
  //     isCredit: open < 0,
  //     isPositiveOpen: open > 0,
  //     statusBadgeClass:
  //       "status-badge " + (open < 0 ? "credit" : statusVal.toLowerCase()),

  //     payAmount: open > 0 ? open : 0
  //   };

  //   this.allInvoices = [newRecord, ...this.allInvoices];

  //   if (newRecord.accountId === this.selectedAccountId) {
  //     this.filterInvoicesByAccount();
  //   } else {
  //     this.selectedAccountId = newRecord.accountId;
  //     this.selectedAccountNumber = newRecord.accountNumber;
  //     this.filterInvoicesByAccount();
  //   }

  //   this.showNewInvoiceModal = false;
  // }

  // View Getters
  get isStepDashboard() {
    return this.currentStep === "dashboard";
  }

  get isStepPayment() {
    return this.currentStep === "payment";
  }

  get isPaymentSuccess() {
    return this.paymentStatus === "success";
  }

  get isPaymentCancel() {
    return this.paymentStatus === "cancel";
  }

  get hasInvoices() {
    return this.filteredInvoices && this.filteredInvoices.length > 0;
  }

  get dashboardMenuItemClass() {
    return "menu-item" + (this.currentStep === "dashboard" ? " active" : "");
  }

  get historyMenuItemClass() {
    return "menu-item" + (this.currentStep === "transactions" ? " active" : "");
  }

  get customersMenuItemClass() {
    return "menu-item" + (this.currentStep === "customers" ? " active" : "");
  }

  get isStepTransactions() {
    return this.currentStep === "transactions";
  }

  get isStepCustomers() {
    return this.currentStep === "customers";
  }

  get selectedInvoices() {
    return this.filteredInvoices.filter((inv) => inv.selected);
  }

  get isAllSelected() {
    const pageInvs = this.paginatedInvoices;
    return pageInvs.length > 0 && pageInvs.every((inv) => inv.selected);
  }

  // Pagination calculations
  get paginatedInvoices() {
    const start = (this.currentPage - 1) * this.pageSize;
    return this.filteredInvoices.slice(start, start + this.pageSize);
  }

  get totalPages() {
    return Math.ceil(this.filteredInvoices.length / this.pageSize) || 1;
  }

  get pagesList() {
    const list = [];
    for (let i = 1; i <= this.totalPages; i++) {
      list.push({
        number: i,
        class: "page-btn" + (i === this.currentPage ? " active" : "")
      });
    }
    return list;
  }

  // Dashboard Statistics Getters (Calculated for current account)
  get accountInvoices() {
    return this.allInvoices.filter(
      (inv) => inv.accountId === this.selectedAccountId
    );
  }

  get accountCurrency() {
    const invoices = this.accountInvoices;
    if (invoices && invoices.length > 0) {
      return invoices[0].currencyKey?.toUpperCase() || "USD";
    }
    return "USD";
  }

  get currencySymbol() {
    const currency = this.accountCurrency;
    if (currency === "EUR") return "€";
    if (currency === "GBP") return "£";
    return "$";
  }

  get currencyOptions() {
    return [
      { label: "USD ($)", value: "USD" },
      { label: "EUR (€)", value: "EUR" },
      { label: "GBP (£)", value: "GBP" }
    ];
  }

  get statusOptions() {
    return [
      { label: "Open", value: "Open" },
      { label: "Credit", value: "Credit" }
    ];
  }

  get totalDue() {
    let total = 0.0;
    this.accountInvoices.forEach((inv) => {
      if (inv.openAmount > 0) {
        total += inv.openAmount;
      }
    });
    return total;
  }

  get totalCredits() {
    let total = 0.0;
    this.accountInvoices.forEach((inv) => {
      if (inv.openAmount < 0) {
        total += Math.abs(inv.openAmount);
      }
    });
    return total;
  }

  get balance() {
    return this.totalDue - this.totalCredits;
  }

  get totalPastDue() {
    let total = 0.0;
    const today = new Date();
    this.accountInvoices.forEach((inv) => {
      if (inv.openAmount > 0 && inv.dueDate) {
        const parts = inv.dueDate.split("/");
        if (parts.length === 3) {
          const dueDate = new Date(parts[2], parts[1] - 1, parts[0]);
          if (dueDate < today) {
            total += inv.openAmount;
          }
        }
      }
    });
    return total;
  }

  // Selected Calculations
  get totalSelectedAmount() {
    let total = 0.0;
    this.filteredInvoices.forEach((inv) => {
      if (inv.selected) {
        total += inv.openAmount;
      }
    });
    return parseFloat(total.toFixed(2));
  }

  get isPayDisabled() {
    return this.totalSelectedAmount <= 0;
  }

  // Session Payment Summary Getters
  get summaryPayAmount() {
    let total = 0.0;
    this.selectedInvoices.forEach((inv) => {
      if (inv.openAmount > 0) {
        total += inv.payAmount;
      }
    });
    return parseFloat(total.toFixed(2));
  }

  get summaryCredits() {
    let total = 0.0;
    this.selectedInvoices.forEach((inv) => {
      if (inv.openAmount < 0) {
        total += Math.abs(inv.openAmount);
      }
    });
    return parseFloat(total.toFixed(2));
  }

  get summaryTotal() {
    return parseFloat((this.summaryPayAmount - this.summaryCredits).toFixed(2));
  }

  // Formatting Getters
  get formattedSelectedAmount() {
    return this.totalSelectedAmount.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  get formattedTotalDue() {
    return this.totalDue.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  get formattedTotalCredits() {
    return this.totalCredits.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  get formattedBalance() {
    return this.balance.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  get formattedPastDue() {
    return this.totalPastDue.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  get formattedSummaryPayAmount() {
    return this.summaryPayAmount.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  get formattedSummaryCredits() {
    return this.summaryCredits.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  get formattedSummaryTotal() {
    return this.summaryTotal.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
  }

  get filteredCustomers() {
    const term = (this.searchTerm || "").trim().toLowerCase();
    if (!term) {
      return this.customers;
    }

    return this.customers.filter((customer) => {
      const value =
        `${customer.name} ${customer.email} ${customer.description}`.toLowerCase();
      return value.includes(term);
    });
  }

  get selectedCustomer() {
    return (
      this.customers.find(
        (customer) => customer.id === this.selectedCustomerId
      ) || null
    );
  }

  get hasCustomers() {
    return this.filteredCustomers && this.filteredCustomers.length > 0;
  }

  get hasPaymentMethods() {
    return this.paymentMethods && this.paymentMethods.length > 0;
  }

  get createCustomerLabel() {
    return this.isCreatingCustomer ? "Creating..." : "Create customer";
  }

  get createPaymentMethodLabel() {
    return this.isCreatingPaymentMethod ? "Saving..." : "Add payment method";
  }

  formatDate(value) {
    if (!value) {
      return "—";
    }

    const date = new Date(value * 1000);
    if (Number.isNaN(date.getTime())) {
      return value;
    }

    return date.toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit"
    });
  }

  getInitials(value) {
    const text = (value || "").trim();
    if (!text) {
      return "C";
    }
    return text.charAt(0).toUpperCase();
  }

  @api
  async loadCustomers() {
    try {
      const result = await listCustomers({ limitUsed: 100 });
      const parsed = typeof result === "string" ? JSON.parse(result) : result;
      const data = Array.isArray(parsed?.data) ? parsed.data : [];

      this.customers = data.map((customer) => ({
        id: customer.id,
        name: customer.name || customer.email || "Customer",
        email: customer.email || "",
        description: customer.description || "",
        isSelected: customer.id === this.selectedCustomerId
      }));

      if (!this.selectedCustomerId && this.customers.length) {
        this.selectedCustomerId = this.customers[0].id;
        this.paymentMethodForm.customerId = this.selectedCustomerId;
      }

      if (!this.selectedPaymentCustomerId && this.customers.length) {
        this.selectedPaymentCustomerId =
          this.selectedCustomerId || this.customers[0].id;
      }

      if (!this.selectedCustomerId) {
        this.paymentMethods = [];
      }
    } catch (error) {
      this.customerError =
        error.body?.message || error.message || "Failed to load customers.";
    }
  }

  async handleRefreshPaymentMethods() {
    this.accountStripeCustomerCache.clear();
    await this.loadAllPaymentMethods(true);
  }

  async loadAllPaymentMethods(forceRefresh = false) {
    this.customerError = "";
    this.customerSuccess = "";
    this.isLoadingPaymentMethods = true;

    try {
      let methods = [];
      let customerIdToFilter = null;

      if (forceRefresh || !this.customers || !this.customers.length) {
        await this.loadCustomers();
      }

      if (this.selectedAccountId) {
        const custData = await this.resolveStripeCustomerForAccount(this.selectedAccountId, forceRefresh);
        if (custData && custData.customerId) {
          customerIdToFilter = custData.customerId;
          if (forceRefresh) {
            try {
              const pmResult = await getCustomerPaymentMethods({ customerId: custData.customerId });
              const parsedPm = typeof pmResult === "string" ? JSON.parse(pmResult) : pmResult;
              methods = Array.isArray(parsedPm?.data) ? parsedPm.data : [];
              custData.paymentMethods = methods;
            } catch (error) {
              console.warn("Failed to load live customer payment methods:", error);
              methods = custData.paymentMethods || [];
            }
          } else {
            methods = custData.paymentMethods || [];
          }
        }
      }

      // If no customer resolved or fallback required, load all payment methods
      if (!customerIdToFilter || methods.length === 0) {
        const result = await listAllPaymentMethods({ limitUsed: 100 });
        const parsed = typeof result === "string" ? JSON.parse(result) : result;
        const allMethods = Array.isArray(parsed?.data) ? parsed.data : [];
        if (customerIdToFilter) {
          methods = allMethods.filter((m) => m.customer === customerIdToFilter);
        } else {
          methods = allMethods;
        }
      }

      this.paymentMethods = methods.map((method) => {
        const customerObj = (this.customers || []).find(
          (c) => c.id === method.customer
        );
        let customerDisplayName = "Not attached";
        if (customerObj) {
          customerDisplayName = `${customerObj.name}`;
        } else if (method.billing_details && method.billing_details.name) {
          customerDisplayName = method.billing_details.name;
        } else if (method.customer) {
          customerDisplayName = method.customer;
        }

        return {
          id: method.id,
          type: method.type,
          typeLabel: method.type ? method.type.toUpperCase() : "CARD",
          status: method.type === "card" ? "Active" : "Saved",
          brand:
            method.card && method.card.brand
              ? method.card.brand.toUpperCase()
              : "CARD",
          last4: method.card ? method.card.last4 : "****",
          expMonth: method.card ? method.card.exp_month : "—",
          expYear: method.card ? method.card.exp_year : "—",
          customerId: method.customer || "Not attached",
          stripeCustomerId: method.customer || "",
          customerName:
            method.billing_details && method.billing_details.name
              ? method.billing_details.name
              : customerObj?.name || "",
          customerEmail:
            method.billing_details && method.billing_details.email
              ? method.billing_details.email
              : customerObj?.email || "",
          customerDisplayName: customerDisplayName,
          created: method.created ? this.formatDate(method.created) : "—"
        };
      });

      // if (!this.paymentMethods.length) {
      //   this.customerError =
      //     "No payment methods were returned by Stripe for this account.";
      // }
    } catch (error) {
      console.error("Payment methods load failed:", error);
      this.customerError =
        error.body?.message ||
        error.message ||
        "Failed to load payment methods.";
    } finally {
      this.isLoadingPaymentMethods = false;
    }
  }

  // openNewPaymentMethodModal() {
  //   const defaultCustId =
  //     this.selectedCustomerId ||
  //     (this.customers[0] ? this.customers[0].id : "");
  //   const defaultCust = this.customers.find((c) => c.id === defaultCustId);
  //   this.paymentMethodForm = {
  //     customerId: defaultCustId,
  //     name: defaultCust ? defaultCust.name : "",
  //     stripeToken: ""
  //   };
  //   this.showPaymentMethodModal = true;
  // }

  // closeNewPaymentMethodModal() {
  //   this.showPaymentMethodModal = false;
  //   this.customerError = "";
  //   this.customerSuccess = "";
  // }

  // async createCustomer() {
  //   if (!this.customerForm.email) {
  //     this.customerError = "Customer email is required.";
  //     return;
  //   }

  //   this.isCreatingCustomer = true;
  //   this.customerError = "";
  //   this.customerSuccess = "";

  //   try {
  //     const response = await createCustomer({
  //       email: this.customerForm.email,
  //       name: this.customerForm.name,
  //       description: this.customerForm.description
  //     });
  //     const parsed = JSON.parse(response);
  //     this.customerSuccess = `Customer ${parsed.email || "created"} successfully.`;
  //     this.customerForm = { email: "", name: "", description: "" };
  //     this.showCustomerForm = false;
  //     await this.loadCustomers();
  //     if (parsed.id) {
  //       this.selectedCustomerId = parsed.id;
  //     }
  //   } catch (error) {
  //     this.customerError =
  //       error.body?.message || error.message || "Unable to create customer.";
  //   } finally {
  //     this.isCreatingCustomer = false;
  //   }
  // }

  // handleCustomerFieldChange(event) {
  //   const field = event.target.dataset.field;
  //   this.customerForm[field] = event.target.value;
  // }

  handlePaymentMethodFieldChange(event) {
    const field = event.target.dataset.field;
    const value = event.target.value;
    this.paymentMethodForm[field] = value;

    if (field === "customerId") {
      this.selectedCustomerId = value;
      this.loadAllPaymentMethods();
    }
  }

  // selectCustomer(event) {
  //   const customerId = event.currentTarget.dataset.id;
  //   this.selectedCustomerId = customerId;
  //   this.customers = this.customers.map((customer) => ({
  //     ...customer,
  //     isSelected: customer.id === customerId
  //   }));
  //   this.paymentMethodForm.customerId = customerId;
  //   this.customerError = "";
  //   this.customerSuccess = "";
  //   this.loadAllPaymentMethods();
  // }

  // handleSearchChange(event) {
  //   this.searchTerm = event.target.value;
  // }

  // toggleCustomerForm() {
  //   this.showCustomerForm = !this.showCustomerForm;
  //   this.customerError = "";
  //   this.customerSuccess = "";
  // }

  async createPaymentMethod() {
    const customerId =
      this.paymentMethodForm.customerId || this.selectedCustomerId;
    if (!customerId) {
      this.customerError = "Select a customer before adding a payment method.";
      return;
    }

    const stripeToken = (this.paymentMethodForm.stripeToken || "").trim();
    if (!stripeToken) {
      this.customerError =
        "A Stripe card token is required. In test mode use tok_visa, tok_mastercard, etc.";
      return;
    }

    this.isCreatingPaymentMethod = true;
    this.customerError = "";
    this.customerSuccess = "";

    try {
      await createPaymentMethodForCustomer({
        customerId: customerId,
        // cardNumber: null,
        // expMonth: null,
        // expYear: null,
        // cvc: null,
        cardholderName: this.paymentMethodForm.name,
        paymentMethodToken: stripeToken
      });

      this.customerSuccess = "Payment method added successfully.";
      this.selectedCustomerId = customerId;
      this.paymentMethodForm = {
        customerId: customerId,
        name: "",
        stripeToken: ""
      };
      this.showPaymentMethodModal = false;
      await this.loadAllPaymentMethods();
      await this.loadCustomers();
    } catch (error) {
      this.customerError =
        error.body?.message || error.message || "Unable to add payment method.";
    } finally {
      this.isCreatingPaymentMethod = false;
    }
  }

  // refreshCustomers() {
  //   return this.loadCustomers();
  // }

  get paginatedStripeTransactions() {
    const start = (this.transactionPage - 1) * this.transactionPageSize;
    return this.stripeTransactions.slice(
      start,
      start + this.transactionPageSize
    );
  }

  get totalTransactionPages() {
    return (
      Math.ceil(this.stripeTransactions.length / this.transactionPageSize) || 1
    );
  }

  get transactionPagesList() {
    const list = [];
    for (let i = 1; i <= this.totalTransactionPages; i++) {
      list.push({
        number: i,
        class: "page-btn" + (i === this.transactionPage ? " active" : "")
      });
    }
    return list;
  }

  get transactionIsFirstPage() {
    return this.transactionPage <= 1;
  }

  get transactionIsLastPage() {
    return this.transactionPage >= this.totalTransactionPages;
  }

  get hasStripeTransactions() {
    return this.stripeTransactions && this.stripeTransactions.length > 0;
  }

  get isAllTransactionsSelected() {
    const pageItems = this.paginatedStripeTransactions;
    return pageItems.length > 0 && pageItems.every((tx) => tx.selected);
  }

  get paymentModeOptions() {
    return [
      { label: "Use saved payment method", value: "existing" },
      { label: "Use new payment method", value: "new" }
    ];
  }

  get paymentCustomerOptions() {
    const options = (this.customers || []).map((customer) => ({
      label: `${customer.name}${customer.email ? " (" + customer.email + ")" : ""}`,
      value: customer.id,
      selected: customer.id === this.selectedPaymentCustomerId
    }));
    return options;
  }

  get activeCustomerFormattedAddress() {
    if (!this.activeStripeCustomer) return "";
    const cust = this.activeStripeCustomer;
    const parts = [
      cust.billingStreet || cust.address?.line1,
      cust.billingCity || cust.address?.city,
      cust.billingState || cust.address?.state,
      cust.billingPostalCode || cust.address?.postal_code,
      cust.billingCountry || cust.address?.country
    ].filter(Boolean);
    return parts.join(", ");
  }

  get customerPaymentMethods() {
    // Use the payment methods loaded specifically for the active Stripe customer.
    // Falls back to filtering the global paymentMethods list for backward compatibility.
    if (this.activeCustomerPaymentMethods && this.activeCustomerPaymentMethods.length > 0) {
      return this.activeCustomerPaymentMethods;
    }
    return (this.paymentMethods || []).filter(
      (method) => method.stripeCustomerId === this.selectedPaymentCustomerId
    );
  }

  get hasCustomerPaymentMethods() {
    return (
      this.customerPaymentMethods && this.customerPaymentMethods.length > 0
    );
  }

  get paymentMethodOptions() {
    const methods = this.customerPaymentMethods.map((method) => ({
      label: `${method.brand} •••• ${method.last4} (${method.expMonth}/${method.expYear})`,
      value: method.id,
      selected: method.id === this.selectedPaymentMethodId
    }));
    return [
      {
        label: "-- Select a saved card --",
        value: "",
        selected: !this.selectedPaymentMethodId
      },
      ...methods
    ];
  }

  get isExistingPaymentMode() {
    return this.paymentMode === "existing";
  }

  get isNewPaymentMode() {
    return this.paymentMode === "new";
  }

  get savedModeClass() {
    return (
      "payment-segment-btn" + (this.isExistingPaymentMode ? " active" : "")
    );
  }

  get newModeClass() {
    return "payment-segment-btn" + (this.isNewPaymentMode ? " active" : "");
  }

  get paymentButtonDisabled() {
    if (
      this.isPayDisabled ||
      this.summaryTotal <= 0 ||
      this.isProcessing ||
      this.isLoadingCustomer ||
      !this.selectedPaymentCustomerId
    ) {
      return true;
    }
    if (this.isExistingPaymentMode) {
      return !this.selectedPaymentMethodId;
    }
    return !this.stripeElementReady || this.stripeElementLoading;
  }

  selectSavedPaymentMode() {
    this.paymentMode = "existing";
    this.paymentError = "";
    this.destroyStripePaymentElement();
  }

  selectNewPaymentMode() {
    this.paymentMode = "new";
    this.paymentError = "";
    this.selectedPaymentMethodId = "";
    this.requestStripeElementRefresh();
  }

  // handlePaymentModeChange(event) {
  //   const value =
  //     event.detail?.value !== undefined
  //       ? event.detail.value
  //       : event.target.value;
  //   this.paymentMode = value;
  //   this.paymentError = "";

  //   if (this.isExistingPaymentMode) {
  //     this.destroyStripePaymentElement();
  //   } else {
  //     this.selectedPaymentMethodId = "";
  //     this.requestStripeElementRefresh();
  //   }
  // }

  handlePaymentCustomerChange(event) {
    const value =
      event.detail?.value !== undefined
        ? event.detail.value
        : event.target.value;
    this.selectedPaymentCustomerId = value;
    this.selectedPaymentMethodId = "";
    this.paymentError = "";
    if (this.isNewPaymentMode) {
      this.requestStripeElementRefresh();
    }
  }

  handlePaymentMethodChange(event) {
    const value =
      event.detail?.value !== undefined
        ? event.detail.value
        : event.target.value;
    this.selectedPaymentMethodId = value;
    this.paymentError = "";
  }

  scheduleStripeElementRefresh() {
    window.clearTimeout(this.stripeRefreshTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.stripeRefreshTimer = window.setTimeout(() => {
      this.requestStripeElementRefresh();
    }, 350);
  }

  requestStripeElementRefresh() {
    this.destroyStripePaymentElement();
    this.paymentError = "";
    if (!this.selectedPaymentCustomerId || this.summaryTotal <= 0) {
      return;
    }
    this.pendingStripeElementInitialization = true;
  }

  destroyStripePaymentElement() {
    // The privileged bridge owns the actual Stripe/Elements objects.
    this.callStripeBridge("destroy", {}, 1500).catch(() => {});
    this.stripeClientSecret = "";
    this.stripeElementReady = false;
    this.stripeElementLoading = false;
  }

  handleStripeBridgeResponse(event) {
    const detail = event?.detail || {};
    if (!detail || detail.bridgeId !== this.stripeBridgeId) {
      return;
    }

    // Asynchronous lifecycle notifications from Stripe Payment Element.
    if (detail.eventType === "ready") {
      this.stripeElementReady = true;
      this.stripeElementLoading = false;
      this.paymentError = "";
      return;
    }

    if (detail.eventType === "change") {
      this.paymentError = detail.errorMessage || "";
      return;
    }

    const pending = detail.requestId
      ? this.stripeBridgeRequests.get(detail.requestId)
      : null;
    if (!pending) {
      return;
    }

    window.clearTimeout(pending.timer);
    this.stripeBridgeRequests.delete(detail.requestId);

    if (detail.ok === false) {
      pending.reject(
        new Error(detail.errorMessage || "Stripe bridge operation failed.")
      );
    } else {
      pending.resolve(detail);
    }
  }

  callStripeBridge(action, payload = {}, timeoutMs = 20000) {
    if (!this.stripeBridgeId) {
      return Promise.reject(new Error("Stripe LWR bridge is not initialized."));
    }

    const requestId = `${this.stripeBridgeId}-${++this.stripeBridgeCounter}`;
    const command = {
      bridgeId: this.stripeBridgeId,
      requestId,
      action,
      ...payload
    };

    return new Promise((resolve, reject) => {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      const timer = window.setTimeout(() => {
        this.stripeBridgeRequests.delete(requestId);
        reject(
          new Error(
            "Stripe privileged bridge did not respond. Confirm the x-oasis-script bridge is present in Experience Cloud Head Markup and the site is published."
          )
        );
      }, timeoutMs);

      this.stripeBridgeRequests.set(requestId, { resolve, reject, timer });
      window.dispatchEvent(
        new CustomEvent("stripe-lwr-command", { detail: command })
      );
    });
  }

  getFinalInvoicesForPayment() {
    return this.selectedInvoices.map((inv) => ({
      ...inv,
      openAmount: inv.openAmount > 0 ? inv.payAmount : inv.openAmount
    }));
  }

  async initializeStripePaymentElement() {
    if (
      !this.isNewPaymentMode ||
      !this.selectedPaymentCustomerId ||
      this.summaryTotal <= 0
    ) {
      return;
    }

    this.stripeElementLoading = true;
    this.stripeElementReady = false;
    this.paymentError = "";

    try {
      if (
        !STRIPE_PUBLISHABLE_KEY ||
        !STRIPE_PUBLISHABLE_KEY.startsWith("pk_")
      ) {
        throw new Error(
          "Stripe publishable key is not configured in Custom Label Stripe_Publishable_Key."
        );
      }

      const finalInvoices = this.getFinalInvoicesForPayment();
      const selectedCurrency = (finalInvoices[0]?.currencyKey || "USD").toLowerCase();
      const amountCents = Math.round(this.summaryTotal * 100);

      const selectedCust = this.customers.find(
        (c) => c.id === this.selectedPaymentCustomerId
      );
      const activeCust = this.activeStripeCustomer || {};
      const customerName = activeCust.name || selectedCust?.name || "";
      const customerEmail = activeCust.email || selectedCust?.email || "";
      const customerPhone = activeCust.phone || "";
      const customerAddress = activeCust.address || (activeCust.billingStreet ? {
        line1: activeCust.billingStreet,
        city: activeCust.billingCity || "",
        state: activeCust.billingState || "",
        postal_code: activeCust.billingPostalCode || "",
        country: activeCust.billingCountry || "US"
      } : null);

      await this.callStripeBridge("mount", {
        publishableKey: STRIPE_PUBLISHABLE_KEY,
        amount: amountCents > 0 ? amountCents : 100,
        currency: selectedCurrency,
        mountAttribute: this.stripeBridgeId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        setupFutureUsage: "off_session"
      });
      // stripeElementReady is set by the bridge's separate `ready` event.
    } catch (error) {
      console.error("Unable to initialize Stripe Payment Element:", error);
      this.paymentError =
        error.body?.message ||
        error.message ||
        "Unable to initialize Stripe Payment Element.";
      this.stripeElementLoading = false;
      this.stripeElementReady = false;
    }
  }

  buildStripeReturnUrl() {
    const url = new URL(window.location.href);
    url.searchParams.delete("payment_intent");
    url.searchParams.delete("payment_intent_client_secret");
    url.searchParams.delete("redirect_status");
    url.searchParams.set("c__payment_status", "stripe_return");
    return url.toString();
  }

  async completeSuccessfulStripePayment(alreadySynced = false) {
    this.paymentStatus = "success";
    this.currentStep = "dashboard";
    this.destroyStripePaymentElement();
    this.accountStripeCustomerCache.clear();

    // Sync the customer's Stripe payment methods to Salesforce Payment_Method__c
    // if not already synced prior to recording the payment.
    if (!alreadySynced && this.selectedAccountId && this.selectedPaymentCustomerId) {
      try {
        await syncPaymentCards({
          accountId: this.selectedAccountId,
          customerId: this.selectedPaymentCustomerId
        });
      } catch (syncError) {
        // Non-fatal: log but don't block the success flow
        console.warn("Payment card sync to Salesforce failed:", syncError);
      }
    }

    this.handleSuccessfulPayment(true);
    await this.loadAllPaymentMethods(true);
  }

  // Existing card: Apex confirms PaymentIntent with pm_xxx.
  // New card: Stripe Payment Element validates inputs, Apex creates PaymentIntent only on Pay, and Stripe.js confirms.
  async handleFinalPay() {
    const selected = this.selectedInvoices;
    if (selected.length === 0 || this.paymentButtonDisabled) {
      return;
    }

    this.isProcessing = true;
    this.paymentError = "";

    const finalInvoices = this.getFinalInvoicesForPayment();
    const selectedCurrency = selected[0]?.currencyKey || "USD";
    const totalPaymentAmount = finalInvoices.reduce((sum, inv) => sum + (parseFloat(inv.openAmount || 0)), 0);
    const paymentPayload = {
      payerAccountId: this.selectedAccountId,
      payerAccountNumber: this.selectedAccountNumber,
      stripeCustomerId: this.selectedPaymentCustomerId || "",
      invoices: finalInvoices
    };
    const payloadString = JSON.stringify(paymentPayload);
    sessionStorage.setItem(this.paymentStorageKey, payloadString);
    localStorage.setItem(this.paymentStorageKey, payloadString);

    let createdPaymentIntentId = "";

    try {
      if (this.isExistingPaymentMode) {
        const result = await createPaymentIntent({
          invoicesJson: JSON.stringify(finalInvoices),
          customerId: this.selectedPaymentCustomerId,
          paymentMethodId: this.selectedPaymentMethodId,
          paymentMethodToken: null,
          cardholderName: null,
          currencyCode: selectedCurrency
        });

        const parsed = typeof result === "string" ? JSON.parse(result) : result;
        createdPaymentIntentId = parsed?.paymentIntentId || "";

        if (parsed?.status === "succeeded") {
          // First create / sync the SF Payment_Method__c
          if (this.selectedAccountId && this.selectedPaymentCustomerId) {
            try {
              await syncPaymentCards({
                accountId: this.selectedAccountId,
                customerId: this.selectedPaymentCustomerId
              });
            } catch (syncError) {
              console.warn("Payment card sync failed:", syncError);
            }
          }

          // Then record the SF Payment record (which links to the SF Payment_Method__c)
          await this.recordPaymentSafely({
            accountId: this.selectedAccountId,
            amount: totalPaymentAmount,
            amountReceived: totalPaymentAmount,
            currencyCode: selectedCurrency,
            paymentIntentId: createdPaymentIntentId,
            paymentMethodId: this.selectedPaymentMethodId || "",
            status: "Paid",
            failureReason: ""
          });
          await this.completeSuccessfulStripePayment(true);
          return;
        }

        // Handle 3DS / requires_action gracefully
        const failStatus = (parsed?.status === "requires_action" || parsed?.status === "requires_payment_method")
          ? "Failed"
          : "Failed";
        const failMessage = (parsed?.status === "requires_action" || parsed?.status === "requires_payment_method")
          ? "This card requires additional authentication (3D Secure). Please use the \"New Payment Method\" option to complete the payment securely."
          : `Stripe payment was not completed. PaymentIntent status: ${parsed?.status || "unknown"}.`;

        await this.recordPaymentSafely({
          accountId: this.selectedAccountId,
          amount: totalPaymentAmount,
          amountReceived: 0,
          currencyCode: selectedCurrency,
          paymentIntentId: createdPaymentIntentId,
          paymentMethodId: this.selectedPaymentMethodId || "",
          status: failStatus,
          failureReason: failMessage
        });

        throw new Error(failMessage);
      }

      if (!this.stripeElementReady) {
        throw new Error("Stripe Payment Element is not ready.");
      }

      const selectedCust = this.customers.find(
        (c) => c.id === this.selectedPaymentCustomerId
      );
      const activeCust = this.activeStripeCustomer || {};
      const customerName = activeCust.name || selectedCust?.name || "";
      const customerEmail = activeCust.email || selectedCust?.email || "";
      const customerPhone = activeCust.phone || "";
      const customerAddress = activeCust.address || (activeCust.billingStreet ? {
        line1: activeCust.billingStreet,
        city: activeCust.billingCity || "",
        state: activeCust.billingState || "",
        postal_code: activeCust.billingPostalCode || "",
        country: activeCust.billingCountry || "US"
      } : null);

      // Step 1: Submit and validate the Payment Element in the iframe before creating any Stripe transaction
      await this.callStripeBridge("submit");

      // Step 2: Create PaymentIntent on server ONLY now after Pay button is clicked & form is valid
      const result = await createPaymentIntentForElement({
        invoicesJson: JSON.stringify(finalInvoices),
        customerId: this.selectedPaymentCustomerId,
        currencyCode: selectedCurrency
      });

      const parsed = typeof result === "string" ? JSON.parse(result) : result;
      this.stripeClientSecret = parsed?.clientSecret || "";
      createdPaymentIntentId = parsed?.paymentIntentId || "";
      if (!this.stripeClientSecret) {
        throw new Error("Stripe did not return a PaymentIntent client secret.");
      }

      // Step 3: Confirm payment with Stripe.js using the newly created PaymentIntent
      const bridgeResult = await this.callStripeBridge(
        "confirm",
        {
          clientSecret: this.stripeClientSecret,
          returnUrl: this.buildStripeReturnUrl(),
          customerName: customerName,
          customerEmail: customerEmail,
          customerPhone: customerPhone,
          customerAddress: customerAddress
        },
        60000
      );
      const paymentIntent = bridgeResult?.paymentIntent;
      const piId = paymentIntent?.id || createdPaymentIntentId;
      const pmId = typeof paymentIntent?.payment_method === "string"
        ? paymentIntent.payment_method
        : paymentIntent?.payment_method?.id || "";

      if (paymentIntent?.status === "succeeded") {
        // Step 1: FIRST create / sync the SF Payment_Method__c
        if (this.selectedAccountId && this.selectedPaymentCustomerId) {
          try {
            await syncPaymentCards({
              accountId: this.selectedAccountId,
              customerId: this.selectedPaymentCustomerId
            });
          } catch (syncError) {
            console.warn("Payment card sync before recordPayment failed:", syncError);
          }
        }

        // Step 2: THEN record the SF Payment record (which links to the newly created SF Payment_Method__c)
        await this.recordPaymentSafely({
          accountId: this.selectedAccountId,
          amount: totalPaymentAmount,
          amountReceived: totalPaymentAmount,
          currencyCode: selectedCurrency,
          paymentIntentId: piId,
          paymentMethodId: pmId,
          status: "Paid",
          failureReason: ""
        });
        await this.completeSuccessfulStripePayment(true);
        return;
      }

      // Redirect-based / 3DS flows can leave this page. The return handler verifies status.
      if (paymentIntent && paymentIntent.status === "processing") {
        await this.recordPaymentSafely({
          accountId: this.selectedAccountId,
          amount: totalPaymentAmount,
          amountReceived: 0,
          currencyCode: selectedCurrency,
          paymentIntentId: piId,
          paymentMethodId: pmId,
          status: "Processing",
          failureReason: ""
        });
        return;
      }

      const failStatus = paymentIntent?.status === "canceled" ? "Canceled" : "Failed";
      const failReason = `Stripe payment was not completed. PaymentIntent status: ${paymentIntent?.status || "unknown"}.`;
      await this.recordPaymentSafely({
        accountId: this.selectedAccountId,
        amount: totalPaymentAmount,
        amountReceived: 0,
        currencyCode: selectedCurrency,
        paymentIntentId: piId,
        paymentMethodId: pmId,
        status: failStatus,
        failureReason: failReason
      });

      throw new Error(failReason);
    } catch (error) {
      console.error("Stripe payment failed:", error);
      sessionStorage.removeItem(this.paymentStorageKey);
      localStorage.removeItem(this.paymentStorageKey);
      this.paymentError =
        error.body?.message ||
        error.message ||
        "Unable to process Stripe payment.";
      this.isProcessing = false;

      // Ensure failure is recorded in Salesforce Payment__c if not already recorded
      await this.recordPaymentSafely({
        accountId: this.selectedAccountId,
        amount: totalPaymentAmount,
        amountReceived: 0,
        currencyCode: selectedCurrency,
        paymentIntentId: createdPaymentIntentId || "",
        paymentMethodId: this.selectedPaymentMethodId || "",
        status: "Failed",
        failureReason: this.paymentError
      });
    }
  }

  async recordPaymentSafely(params) {
    if (!params || !params.accountId) {
      return;
    }
    try {
      await recordPayment({
        accountId: params.accountId,
        amount: params.amount != null ? parseFloat(params.amount) : 0,
        amountReceived: params.amountReceived != null ? parseFloat(params.amountReceived) : 0,
        currencyCode: params.currencyCode || "USD",
        paymentIntentId: params.paymentIntentId || "",
        paymentMethodId: params.paymentMethodId || "",
        status: params.status || "Pending",
        failureReason: (params.failureReason || "").substring(0, 255)
      });
    } catch (recErr) {
      console.warn("recordPayment to Salesforce failed:", recErr);
    }
  }

  get paymentStorageKey() {
    return PAYMENT_PAYLOAD_KEY;
  }

  updateLocalInvoiceAmounts(invoiceUpdates) {
    if (!invoiceUpdates || invoiceUpdates.length === 0) {
      return;
    }

    const updatedInvoices = this.allInvoices.map((inv) => {
      const update = invoiceUpdates.find(
        (item) => item.invoiceId === inv.invoiceId
      );
      if (!update) {
        return inv;
      }

      const existingOpen = inv.openAmount != null ? inv.openAmount : 0;
      const existingPaid = inv.paidAmount != null ? inv.paidAmount : 0;
      const paymentAmount =
        update.paymentAmount != null ? update.paymentAmount : 0;
      let newOpen = existingOpen - paymentAmount;
      let newPaid = existingPaid + paymentAmount;

      if (existingOpen > 0 && newOpen < 0) {
        newOpen = 0;
      } else if (existingOpen < 0 && newOpen > 0) {
        newOpen = 0;
      }

      return {
        ...inv,
        paidAmount: newPaid,
        openAmount: newOpen,
        formattedPaid: newPaid.toLocaleString("en-US", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2
        }),
        formattedOpen: newOpen.toLocaleString("en-US", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2
        }),
        formattedOpenAbs: Math.abs(newOpen).toLocaleString("en-US", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2
        }),
        isPaid: newOpen === 0,
        isCredit: newOpen < 0,
        isPositiveOpen: newOpen > 0,
        statusBadgeClass:
          "status-badge " +
          (newOpen < 0 ? "credit" : newOpen === 0 ? "paid" : "open")
      };
    });

    this.allInvoices = updatedInvoices;
    this.filterInvoicesByAccount();
  }

  handleSuccessfulPayment(alreadySynced = false) {
    let storedPayload = sessionStorage.getItem(this.paymentStorageKey);
    if (!storedPayload) {
      storedPayload = localStorage.getItem(this.paymentStorageKey);
    }
    if (!storedPayload) {
      return;
    }

    const payload = JSON.parse(storedPayload);
    const invoices = Array.isArray(payload) ? payload : payload.invoices || [];

    if (payload.payerAccountId) {
      this.selectedAccountId = payload.payerAccountId;
      this.selectedAccountNumber =
        payload.payerAccountNumber || this.selectedAccountNumber;
    }

    const invoiceUpdates = invoices
      .map((inv) => ({
        invoiceId: inv.invoiceId,
        paymentAmount: parseFloat(inv.payAmount || 0)
      }))
      .filter((item) => item.paymentAmount > 0 && item.invoiceId);

    const invoiceUpdatesPayload = JSON.parse(JSON.stringify(invoiceUpdates));
    if (invoiceUpdatesPayload.length === 0) {
      sessionStorage.removeItem(this.paymentStorageKey);
      localStorage.removeItem(this.paymentStorageKey);
      return;
    }

    // Update UI first so the invoice row reflects the successful payment immediately.
    this.updateLocalInvoiceAmounts(invoiceUpdatesPayload);

    const plainInvoiceUpdates = JSON.parse(
      JSON.stringify(invoiceUpdatesPayload)
    );
    applyInvoicePaymentsJson({
      invoicePaymentsJson: JSON.stringify(plainInvoiceUpdates)
    })
      .then((result) => {
        sessionStorage.removeItem(this.paymentStorageKey);
        localStorage.removeItem(this.paymentStorageKey);
        this.isProcessing = false;
        if (result === 0) {
          console.warn("InvoiceList: applyInvoicePayments updated 0 records");
        }
        this.loadInvoicesForSelectedAccount();

        // Sync payment cards to Salesforce after successful payment (redirect/return path only if not already synced).
        if (!alreadySynced) {
          const syncAccountId = payload.payerAccountId || this.selectedAccountId;
          const syncCustomerId = payload.stripeCustomerId || this.selectedPaymentCustomerId;
          if (syncAccountId && syncCustomerId) {
            syncPaymentCards({ accountId: syncAccountId, customerId: syncCustomerId })
              .then(() => {
                this.accountStripeCustomerCache.clear();
                this.loadAllPaymentMethods(true);
              })
              .catch((err) => console.warn("Post-redirect card sync failed:", err));
          }
        }
      })
      .catch((error) => {
        console.error("Error applying invoice payments:", error);
        this.isProcessing = false;
      });
  }
}