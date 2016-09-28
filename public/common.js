$(function () {
  // クラスを追加、削除した方がいいな。
  $('.media').on('mouseenter', function () {
    $(this).css('background-color', '#f0f0f0');
  });
  $('.media').on('mouseleave', function () {
    $(this).css('background-color', 'transparent');
  });
});
