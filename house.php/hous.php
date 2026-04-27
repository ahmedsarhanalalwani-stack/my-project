<?php
// 1. الاتصال بقاعدة البيانات
$host = "b5ln4zf96ckpczcvplc8-mysql.services.clever-cloud.com";
$user = "u6n1ksn2sqymye8m";
$pass = "1IalPp2L5tKQlzgGgWai";
$db   = "b5ln4zf96ckpczcvplc8";

$conn = mysqli_connect($host, $user, $pass, $db);
mysqli_set_charset($conn, "utf8");

// 2. معالجة تحديث البيانات (عند الضغط على الأزرار)
if (isset($_GET['action'])) {
    $id = $_GET['id'];
    if ($_GET['action'] == 'toggle_clean') {
        mysqli_query($conn, "UPDATE students SET cleaning_status = NOT cleaning_status WHERE id = $id");
    } elseif ($_GET['action'] == 'toggle_rent') {
        mysqli_query($conn, "UPDATE students SET rent_paid = NOT rent_paid WHERE id = $id");
    }
    header("Location: hous.php"); // إعادة تحميل الصفحة لتحديث البيانات
}
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>نظام إدارة سكن الطلاب</title>
    <style>
        :root { --primary: #2c3e50; --accent: #3498db; --success: #27ae60; --danger: #e74c3c; }
        body { font-family: 'Segoe UI', Arial, sans-serif; background-color: #f0f2f5; margin: 0; padding: 20px; }
        .container { max-width: 1000px; margin: auto; background: white; padding: 20px; border-radius: 12px; box-shadow: 0 5px 15px rgba(0,0,0,0.1); }
        h2 { color: var(--primary); text-align: center; border-bottom: 2px solid var(--accent); padding-bottom: 10px; }
        
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: var(--primary); color: white; padding: 12px; text-align: right; }
        td { padding: 12px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f9f9f9; }

        .btn { padding: 6px 12px; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; font-size: 14px; }
        .btn-check { background: #eee; color: #333; }
        .btn-check.active { background: var(--success); color: white; }
        
        .status-badge { padding: 4px 8px; border-radius: 20px; font-size: 12px; font-weight: bold; }
        .committed { background: #d4edda; color: #155724; }
        .not-committed { background: #f8d7da; color: #721c24; }
        
        @media (max-width: 600px) {
            table, thead, tbody, th, td, tr { display: block; }
            th { text-align: center; }
            td { text-align: center; border: none; border-bottom: 1px solid #eee; }
        }
    </style>
</head>
<body>

<div class="container">
    <h2>🏠 لوحة تحكم سكن الطلاب</h2>

    <table>
        <thead>
            <tr>
                <th>الطالب</th>
                <th>الغرفة</th>
                <th>النظافة</th>
                <th>الإيجار/الفواتير</th>
                <th>الحالة العامة</th>
            </tr>
        </thead>
        <tbody>
            <?php
            $result = mysqli_query($conn, "SELECT * FROM students");
            if (mysqli_num_rows($result) > 0) {
                while($row = mysqli_fetch_assoc($result)) {
                    $status_class = ($row['rent_paid'] && $row['cleaning_status']) ? 'committed' : 'not-committed';
                    $status_text = ($row['rent_paid'] && $row['cleaning_status']) ? 'ملتزم' : 'غير ملتزم';
                    
                    echo "<tr>
                            <td>{$row['full_name']}<br><small>{$row['phone']}</small></td>
                            <td>{$row['room_number']}</td>
                            <td>
                                <a href='?action=toggle_clean&id={$row['id']}' class='btn btn-check " . ($row['cleaning_status'] ? 'active' : '') . "'>
                                    " . ($row['cleaning_status'] ? '✔️ تم' : '❌ لم يتم') . "
                                </a>
                            </td>
                            <td>
                                <a href='?action=toggle_rent&id={$row['id']}' class='btn btn-check " . ($row['rent_paid'] ? 'active' : '') . "'>
                                    " . ($row['rent_paid'] ? '💰 مدفوع' : '💸 مطلوب') . "
                                </a>
                            </td>
                            <td><span class='status-badge {$status_class}'>{$status_text}</span></td>
                          </tr>";
                }
            } else {
                echo "<tr><td colspan='5' style='text-align:center;'>لا يوجد طلاب مسجلين حالياً</td></tr>";
            }
            ?>
        </tbody>
    </table>
</div>

</body>
</html>