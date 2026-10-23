<script lang="ts">
    export let isAr = false;
</script>

<section
    id="aqura-vikin-extension"
    class="mb-10 rounded-xl border border-blue-100 bg-blue-50/40 p-5 sm:p-6"
    lang={isAr ? 'ar' : 'en'}
    dir={isAr ? 'rtl' : 'ltr'}
    aria-labelledby="vikin-extension-privacy-title"
>
    <h2 id="vikin-extension-privacy-title" class="text-2xl font-bold text-gray-900">
        {isAr ? 'خصوصية إضافة Aqura-vikin' : 'Aqura-vikin Extension privacy'}
    </h2>
    <p class="mt-2 text-sm text-gray-600">
        {isAr
            ? 'تاريخ السريان: 23 أكتوبر 2026. الناشر: Aqura. يختص هذا القسم بإضافة Aqura-vikin الإصدار 0.4.0، وتُقدَّم أحكامه على العبارات العامة في سياسة الموقع فيما يتعلق بمعالجة بيانات الإضافة. وتظل السياسة العامة سارية على خدمات Aqura الأخرى.'
            : 'Effective date: 23 October 2026. Publisher: Aqura. This section specifically governs Aqura-vikin Extension version 0.4.0 and takes precedence over general website-policy statements about the extension’s data handling. The general policy continues to apply to other Aqura services.'}
    </p>

    <div class="mt-6 space-y-6 text-gray-700 leading-relaxed">
        <section>
            <h3 class="mb-2 text-lg font-semibold text-gray-900">{isAr ? 'الغرض وتحكم المستخدم' : 'Purpose and user control'}</h3>
            {#if isAr}
                <p>تربط إضافة Aqura-vikin علامة تبويب Vikin التي سجلت الدخول إليها مسبقاً على <a href="https://reports.viknbooks.com" class="text-blue-700 underline" dir="ltr">reports.viknbooks.com</a> بتطبيق Aqura AI Assistant متوافق يعمل على جهاز Windows نفسه. تنفذ الإضافة مزامنة دفاتر الحسابات ومهام القيود اليومية التي تبدأها صراحة في المساعد. تثبيت الإضافة أو إقرانها لا يبدأ جمع دفاتر الحسابات أو ترحيل أي قيد.</p>
                <p class="mt-2">للإقران، أنشئ رمزاً لمرة واحدة من <span dir="ltr">Vikin Skills &gt; Pair Browser</span> في المساعد وأدخله في النافذة المنبثقة للإضافة. تنتهي صلاحية الرمز بعد عشر دقائق. يتيح الإقران اتصال هذا المتصفح بالمساعد؛ وتظل المهام مرتبطة بإجراءات تبدأها أنت.</p>
            {:else}
                <p>Aqura-vikin Extension connects your existing signed-in Vikin tab at <a href="https://reports.viknbooks.com" class="text-blue-700 underline">reports.viknbooks.com</a> to a compatible Aqura AI Assistant running on the same Windows computer. It performs ledger synchronization and journal-voucher tasks that you explicitly start in the Assistant. Installing or pairing the extension does not start ledger collection or journal posting.</p>
                <p class="mt-2">To pair, generate a one-time code in the Assistant's <strong>Vikin Skills &gt; Pair Browser</strong> and enter it in the extension popup. The code expires after ten minutes. Pairing connects this browser to the Assistant; work remains tied to tasks you start.</p>
            {/if}
        </section>

        <section>
            <h3 class="mb-2 text-lg font-semibold text-gray-900">{isAr ? 'المعلومات التي تعالجها الإضافة' : 'Information handled'}</h3>
            {#if isAr}
                <ul class="list-disc ps-6 space-y-2">
                    <li><strong>الاتصال:</strong> رمز الإقران لمرة واحدة، ورمز الوصول المحلي الناتج، وحالة الإقران، ومعرفات المهام اللازمة للاتصال بالمساعد.</li>
                    <li><strong>مزامنة دفاتر الحسابات:</strong> أسماء دفاتر الحسابات ورموزها وأسماء مجموعات الحسابات، وسياق شركة Vikin المعنية. قد تتضمن أسماء الدفاتر أسماء موظفين أو أسماء أشخاص آخرين.</li>
                    <li><strong>القيود اليومية المكلّف بها:</strong> سياق الشركة وأسماء دفاتر الحسابات ورموزها وتواريخ الترحيل والمبالغ المدينة والدائنة والبيانات الوصفية وأرقام السندات ومعلومات التأكيد أو الخطأ اللازمة لإعداد القيد وإرساله والتحقق منه. قد تتضمن قيود الرواتب أسماء موظفين ومعلومات مالية.</li>
                    <li><strong>استعادة حالة الحفظ:</strong> سجل صغير لحالة الحفظ المعلّقة في تخزين جلسة علامة تبويب Vikin، يتضمن معرف المهمة ورقم السند والتاريخ والإجمالي، للمساعدة على منع تكرار الضغط على Save بعد التنقل أو عند عدم التأكد من النتيجة.</li>
                </ul>
                <p class="mt-3">لا تقرأ الإضافة كلمات مرور Vikin أو ملفات تعريف الارتباط في المتصفح أو رموز مصادقة موقع Vikin. ولا تجمع سجل التصفح العام أو تقرأ مواقع غير مرتبطة بالمهام. لا تقرأ أرصدة الحسابات لمزامنة دفاتر الحسابات؛ وتقرأ القيم المعروضة في القيد وإثبات حفظه بالقدر اللازم للتحقق من مهمة القيد المكلّف بها.</p>
            {:else}
                <ul class="list-disc ps-6 space-y-2">
                    <li><strong>Connection:</strong> the one-time pairing code, resulting local capability token, pairing status, and task identifiers needed to connect to the Assistant.</li>
                    <li><strong>Ledger synchronization:</strong> ledger names, ledger codes, account-group names, and relevant Vikin company context. Ledger names can contain employee or other personal names.</li>
                    <li><strong>Assigned journal vouchers:</strong> company context, ledger names and codes, posting dates, debit and credit amounts, narrations, voucher numbers, and confirmation or error information needed to prepare, submit, and verify the assigned voucher. Payroll entries can contain employee names and financial information.</li>
                    <li><strong>Save recovery:</strong> a small pending-save record in Vikin tab session storage, including task identifier, voucher number, date, and total, helps prevent another Save click after navigation or an uncertain result.</li>
                </ul>
                <p class="mt-3">The extension does not read Vikin passwords, browser cookies, or Vikin authentication tokens. It does not collect general browsing history or read unrelated websites. It does not read account balances for ledger synchronization; the assigned journal-voucher workflow reads displayed voucher and receipt values as needed for verification.</p>
            {/if}
        </section>

        <section>
            <h3 class="mb-2 text-lg font-semibold text-gray-900">{isAr ? 'استخدام البيانات ونقلها' : 'Use and transmission'}</h3>
            {#if isAr}
                <p>تُستخدم البيانات لتوصيل المتصفح بالمساعد المحلي وتنفيذ أعمال Vikin المكلّف بها صراحة وإبلاغ المساعد بالتقدم والنتيجة. يجري تبادل بيانات المهام مع <code dir="ltr">http://127.0.0.1:18765</code> على الجهاز نفسه. هذا اتصال HTTP محلي عبر عنوان loopback، وليس اتصال إنترنت مشفراً. يصادق رمز الوصول على طلبات الاتصال المحلي.</p>
                <p class="mt-2">تعمل الإضافة من خلال صفحة Vikin الحالية. عندما تسمح مهمة ترحيل تبدأها صراحة بالحفظ، يُرسل نموذج القيد إلى Vikin عبر اتصال HTTPS المعتاد للموقع. ترسل الإضافة نتائج الدفاتر والمهام إلى المساعد المحلي، وقد يزامن المساعد البيانات المطلوبة أو حالة المهمة مع قاعدة بيانات Aqura المصرح لك بها باستخدام جلسة Aqura الخاصة بك. لا تتصل الإضافة مباشرة بقاعدة بيانات Aqura أو بخادم منفصل للناشر.</p>
                <p class="mt-2">يتلقى Vikin ومشغّل نظام Aqura الخاص بك البيانات اللازمة للعمل الذي طلبته. تسري سياسات التخزين والوصول الخاصة بهما على السجلات المحفوظة لديهما.</p>
            {:else}
                <p>Data is used to connect the browser to the local Assistant, carry out explicitly assigned Vikin work, and report progress and results. The extension exchanges task data with <code>http://127.0.0.1:18765</code> on the same computer. This is a loopback HTTP connection, not an encrypted internet connection. The capability token authenticates local bridge requests.</p>
                <p class="mt-2">The extension acts through the existing Vikin page. When an explicitly assigned posting task enables Save, the voucher form is submitted to Vikin through the page's normal HTTPS connection. The extension sends ledger and task results to the local Assistant. The Assistant may synchronize requested data or task status to your authorized Aqura database using your Aqura session. The extension does not contact an Aqura database or a separate publisher server directly.</p>
                <p class="mt-2">Vikin and the operator of your Aqura deployment receive data needed for your requested work. Their storage and access policies apply to records those services keep.</p>
            {/if}
        </section>

        <section>
            <h3 class="mb-2 text-lg font-semibold text-gray-900">{isAr ? 'التخزين والاحتفاظ والإزالة' : 'Storage, retention, and removal'}</h3>
            {#if isAr}
                <p>يُحفظ رمز الإقران المحلي في <code dir="ltr">chrome.storage.local</code> داخل ملف المتصفح مع تقييد وصول نصوص المحتوى إليه. يحفظ المساعد بيانات اعتماده بشكل منفصل في Windows Credential Manager. لا تتضمن حزمة الإضافة سراً مشتركاً. يبقى رمز المتصفح حتى تختار Disconnect أو تمسح تخزين الإضافة أو تزيلها.</p>
                <p class="mt-2">يزيل Disconnect نسخة المتصفح ويطلب من المساعد الجاري تشغيله إلغاء الإقران. إذا تعذر إكمال الإلغاء، مثلاً لأن المساعد غير متاح أو مشغول، فاستخدم أداة إعادة تعيين إقرانات المتصفحات في المساعد عندما لا تكون هناك مهمة قيد التشغيل لإلغاء الوصول المحفوظ. إزالة الإقران لا تحذف سجلات الأعمال التي أُنشئت بالفعل في Vikin أو Aqura.</p>
                <p class="mt-2">تُعالج بيانات المهام في ذاكرة التشغيل. قد يبقى سجل استعادة الحفظ في تخزين جلسة علامة تبويب Vikin بعد إعادة تحميل الصفحة، وقد يعيده المتصفح عند استعادة الجلسة. يمكن إزالته بمسح بيانات جلسة الموقع. لا تمسح سجل حفظ معلّق لإعادة محاولة ترحيل غير مؤكد؛ تحقّق أولاً من السند الموجود. إزالة الإضافة لا تعكس قيداً محفوظاً ولا تحذف تخزين موقع Vikin أو سجلات قاعدة بيانات Aqura.</p>
                <p class="mt-2">تتحكم مؤسستك والخدمات المعنية في الاحتفاظ بسجلات المحاسبة والرواتب وحذفها في Vikin وAqura. تواصل مع المسؤول المختص لطلب تعديل تلك السجلات أو حذفها.</p>
            {:else}
                <p>The local pairing token is kept in the browser profile's <code>chrome.storage.local</code>, with content-script access restricted. The Assistant stores its credential separately in Windows Credential Manager. No shared secret is included in the extension package. The browser token remains until you choose Disconnect, clear extension storage, or uninstall the extension.</p>
                <p class="mt-2">Disconnect removes the browser copy and asks the running Assistant to revoke the pairing. If revocation cannot be completed, for example because the Assistant is unavailable or busy, use the Assistant's browser-pairing reset control when no task is running to revoke saved access. Removing a pairing does not erase business records already created in Vikin or Aqura.</p>
                <p class="mt-2">Task data is processed in runtime memory. The pending-save recovery record in Vikin tab session storage can survive reloads and may be restored by the browser's session-restoration behavior. It can be removed by clearing the site's session data. Do not clear a pending-save record to retry an uncertain posting: reconcile the existing voucher first. Uninstalling the extension does not reverse a saved voucher or delete Vikin site storage or Aqura database records.</p>
                <p class="mt-2">Retention and deletion of accounting and payroll records in Vikin and Aqura are controlled by your organization and those services. Contact the appropriate administrator to request changes to those records.</p>
            {/if}
        </section>

        <section>
            <h3 class="mb-2 text-lg font-semibold text-gray-900">{isAr ? 'عدم التتبع والاستخدام المحدود' : 'No tracking and Limited Use'}</h3>
            {#if isAr}
                <p>لا تضيف الإضافة إعلانات أو تحليلات، ولا ترسل البيانات إلى جهات إعلانية أو تحليلية أو وسطاء بيانات. لا تُباع بيانات الإضافة ولا تُستخدم للإعلانات أو لتقييم الجدارة الائتمانية أو اتخاذ قرارات الإقراض. يقتصر الاستخدام والنقل على الغرض المعلن للإضافة وفق سياسة بيانات المستخدم في Chrome Web Store، بما فيها متطلبات Limited Use.</p>
            {:else}
                <p>The extension adds no advertising or analytics and has no advertising recipient, analytics recipient, or data broker. Extension data is not sold or used for advertising, creditworthiness, or lending decisions. Use and transfer are limited to the extension's stated purpose in accordance with the Chrome Web Store User Data Policy, including its Limited Use requirements.</p>
            {/if}
        </section>

        <section>
            <h3 class="mb-2 text-lg font-semibold text-gray-900">{isAr ? 'التغييرات والتواصل' : 'Changes and contact'}</h3>
            {#if isAr}
                <p>تُحدَّث هذه السياسة عند تغير ممارسات البيانات. يتطلب أي استخدام مختلف جوهرياً للبيانات الشخصية أو الحساسة إفصاحاً مناسباً داخل المنتج وموافقة قبل بدء ذلك الاستخدام. لأسئلة الخصوصية أو الدعم المتعلقة بهذه الإضافة، تواصل مع Aqura على <a href="mailto:support@urbanaqura.com" class="text-blue-700 underline" dir="ltr">support@urbanaqura.com</a>.</p>
            {:else}
                <p>This policy will be updated when data practices change. A materially different use of personal or sensitive data requires an appropriate in-product disclosure and consent before that use begins. For extension privacy questions or support, contact Aqura at <a href="mailto:support@urbanaqura.com" class="text-blue-700 underline">support@urbanaqura.com</a>.</p>
            {/if}
        </section>
    </div>
</section>
