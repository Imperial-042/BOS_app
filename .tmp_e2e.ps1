$base='https://skflmtjkxqelkzontcpw.supabase.co'
$key='sb_publishable_TYunykvN_zyyuDYzjkXsLw_7WtKjubU'
function NewUser($name) {
  $email="bos.$(Get-Random)@example.com"
  $body=@{email=$email;password='TestPass123!';data=@{display_name=$name}} | ConvertTo-Json
  $r=Invoke-RestMethod -Uri "$base/auth/v1/signup" -Method Post -Headers @{'apikey'=$key;'Content-Type'='application/json'} -Body $body
  return @{ id=$r.user.id; tok=$r.access_token }
}
function AuthH($tok){ @{'apikey'=$key;'Authorization'="Bearer $tok";'Content-Type'='application/json'} }

$a = NewUser 'User A'
$pa = Invoke-RestMethod -Uri "$base/rest/v1/profiles?id=eq.$($a.id)" -Headers (AuthH $a.tok)
"A_PROFILE displayName=$($pa[0].display_name) matchesId=$($pa[0].id -eq $a.id)"

$bizA = Invoke-RestMethod -Uri "$base/rest/v1/rpc/create_business_with_owner" -Method Post -Headers (AuthH $a.tok) -Body (@{p_name='My Store';p_business_type='retailer';p_industry='Grocery'} | ConvertTo-Json)
"A_BIZ id=$bizA"
$mA = Invoke-RestMethod -Uri "$base/rest/v1/business_memberships?business_id=eq.$bizA" -Headers (AuthH $a.tok)
"A_MEMBERSHIP role=$($mA[0].role) status=$($mA[0].status)"

Invoke-RestMethod -Uri "$base/rest/v1/customers" -Method Post -Headers (AuthH $a.tok) -Body (@{business_id=$bizA;name='John'} | ConvertTo-Json) | Out-Null
$cA = Invoke-RestMethod -Uri "$base/rest/v1/customers?business_id=eq.$bizA" -Headers (AuthH $a.tok)
"A_CUSTOMER rows=$($cA.Count) name=$($cA[0].name)"

$b = NewUser 'User B'
$bizB = Invoke-RestMethod -Uri "$base/rest/v1/rpc/create_business_with_owner" -Method Post -Headers (AuthH $b.tok) -Body (@{p_name='My Store';p_business_type='service_provider'} | ConvertTo-Json)
Invoke-RestMethod -Uri "$base/rest/v1/customers" -Method Post -Headers (AuthH $b.tok) -Body (@{business_id=$bizB;name='John'} | ConvertTo-Json) | Out-Null

$readA = Invoke-RestMethod -Uri "$base/rest/v1/customers?business_id=eq.$bizA" -Headers (AuthH $b.tok)
"B_READ_A_CUSTOMERS rows=$($readA.Count) (expect 0)"

try {
  Invoke-RestMethod -Uri "$base/rest/v1/customers" -Method Post -Headers (AuthH $b.tok) -Body (@{business_id=$bizA;name='Intruder'} | ConvertTo-Json) -ErrorAction Stop | Out-Null
  "B_INSERT_INTO_A ALLOWED! (RLS HOLE)"
} catch { "B_INSERT_INTO_A blocked status=$($_.Exception.Response.StatusCode.value__)" }

$cB = Invoke-RestMethod -Uri "$base/rest/v1/customers?business_id=eq.$bizB" -Headers (AuthH $b.tok)
"B_OWN_CUSTOMERS rows=$($cB.Count) (expect 1)"
