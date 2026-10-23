$base='https://skflmtjkxqelkzontcpw.supabase.co'
$key='sb_publishable_TYunykvN_zyyuDYzjkXsLw_7WtKjubU'
$body=@{email="bos.diag.$(Get-Random)@example.com";password='TestPass123!';data=@{display_name='Diag'}} | ConvertTo-Json
$r=Invoke-RestMethod -Uri "$base/auth/v1/signup" -Method Post -Headers @{'apikey'=$key;'Content-Type'='application/json'} -Body $body
$h=@{'apikey'=$key;'Authorization'="Bearer $($r.access_token)";'Content-Type'='application/json'}
$biz=Invoke-RestMethod -Uri "$base/rest/v1/rpc/create_business_with_owner" -Method Post -Headers $h -Body (@{p_name='Diag Store'} | ConvertTo-Json)
"biz=$biz"
try {
  Invoke-RestMethod -Uri "$base/rest/v1/customers" -Method Post -Headers $h -Body (@{business_id=$biz;name='John'} | ConvertTo-Json) -ErrorAction Stop | Out-Null
  "CUSTOMER_INSERT OK"
} catch {
  $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
  "CUSTOMER_INSERT_ERR: " + $reader.ReadToEnd()
}
